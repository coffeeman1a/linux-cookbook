package handlers

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
	"webhook-handler/internal/config"
	"webhook-handler/internal/models"
)

// healthcheck endpoint
func PingHandler(w http.ResponseWriter, req *http.Request) {
	log.Printf("[PING] %s %s from %s", req.Method, req.URL.Path, req.RemoteAddr)
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "pong\n")
}

// start-vm endpoint
func StartVMHandler(w http.ResponseWriter, req *http.Request) {
	log.Printf("[START-VM] %s %s from %s", req.Method, req.URL.Path, req.RemoteAddr)

	var reqBody models.StartVMRequest
	if err := json.NewDecoder(req.Body).Decode(&reqBody); err != nil {
		log.Printf("[ERROR] invalid payload: %v", err)
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}

	inst, ok := config.C.Proxmox[reqBody.Cluster]
	if !ok {
		log.Printf("[ERROR] unknown cluster: %s", reqBody.Cluster)
		http.Error(w, "unknown cluster", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(req.Context(), 15*time.Second)
	defer cancel()

	err := startVM(ctx, inst.APIURL, inst.APITokenID, inst.APITokenSecret, reqBody.Node, reqBody.VMID)
	if err != nil {
		log.Printf("[ERROR] startVM failed for cluster=%s node=%s vmid=%d: %v", reqBody.Cluster, reqBody.Node, reqBody.VMID, err)
		resp := models.APIResponse{Success: false, Error: err.Error()}
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(resp)
		notifyOOMFailed(reqBody.Node, reqBody.VMID, err)
		return
	}
	log.Printf("[INFO] VM started: cluster=%s node=%s vmid=%d", reqBody.Cluster, reqBody.Node, reqBody.VMID)
	notifyOOMResolved(reqBody.Node, reqBody.VMID)

	err = deleteOOMGauge(ctx, config.C.Proxmox[reqBody.Cluster].PUSHGATEWAY, reqBody.Cluster, reqBody.Node, reqBody.VMID)
	if err != nil {
		log.Printf("[ERROR] deleteOOMGauge failed for apiURL=%s cluster=%s node=%s vmid=%d: %v", config.C.Proxmox[reqBody.Cluster].PUSHGATEWAY, reqBody.Cluster, reqBody.Node, reqBody.VMID, err)
		resp := models.APIResponse{Success: false, Error: err.Error()}
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(resp)
		return
	}
	log.Printf("[INFO] metric oom_killer_event deleted: apiURL=%s cluster=%s node=%s vmid=%d", config.C.Proxmox[reqBody.Cluster].PUSHGATEWAY, reqBody.Cluster, reqBody.Node, reqBody.VMID)

	json.NewEncoder(w).Encode(models.APIResponse{Success: true})
}

// Proxmox API call
func startVM(ctx context.Context, apiURL, tokenID, tokenSecret, node string, vmID int) error {
	url := fmt.Sprintf("%s/nodes/%s/qemu/%d/status/start", apiURL, node, vmID)
	log.Printf("[CALL] POST %s", url)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Authorization", fmt.Sprintf("PVEAPIToken=%s=%s", tokenID, tokenSecret))
	req.Header.Set("Accept", "application/json")

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	client := &http.Client{Transport: tr, Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("bad status: %s", resp.Status)
	}
	return nil
}

func deleteOOMGauge(ctx context.Context, apiURL, cluster, node string, vm_id int) error {
	url := fmt.Sprintf("%s/metrics/job/oom_killer/cluster/%s/node/%s/vm_id/%d", apiURL, cluster, node, vm_id)
	log.Printf("[CALL] DELETE %s", url)
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	client := &http.Client{Transport: tr, Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		return fmt.Errorf("bad status: %s", resp.Status)
	}
	return nil
}

func sendMessage(text string) error {
	botToken := config.C.Telegram.BotToken
	chatID := config.C.Telegram.ChatID
	apiURL := config.C.Telegram.APIURL

	url := fmt.Sprintf("%s/bot%s/sendMessage", apiURL, botToken)

	body := models.SendTelegramMessageReq{
		ChatID: chatID,
		Text:   text,
	}
	buf, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal telegram payload: %w", err)
	}

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Post(url, "application/json", bytes.NewBuffer(buf))
	if err != nil {
		return fmt.Errorf("post to telegram: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("telegram API returned %s", resp.Status)
	}
	return nil
}

func notifyOOMResolved(node string, vmID int) {
	text := fmt.Sprintf(
		"✅ OOM устранён\n"+
			"Нода: %s\n"+
			"ВМ: %d\n",
		node, vmID,
	)
	if err := sendMessage(text); err != nil {
		log.Printf("[ERROR] norifyOOMResolved failed to send status: %v", err)
	}
}

func notifyOOMFailed(node string, vmID int, err error) {
	text := fmt.Sprintf(
		"❌ OOM не устранён\n"+
			"Нода: %s\n"+
			"ВМ: %d\n"+
			"%v",
		node, vmID, err,
	)
	if err := sendMessage(text); err != nil {
		log.Printf("[ERROR] notifyOOMFailed failed to send status: %v", err)
	}
}

// Wrapper function enforcing HTTP method
func MethodHandler(method string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		if req.Method != method {
			log.Printf("[WARN] method not allowed: expected %s, got %s", method, req.Method)
			w.Header().Set("Allow", method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			fmt.Fprintf(w, "method %s is not allowed\n", req.Method)
			return
		}
		h(w, req)
	}
}
