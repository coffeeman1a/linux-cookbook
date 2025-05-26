package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"simple_http_server/internal/config"
	"simple_http_server/internal/models"
	"time"
)

func pingHandler(w http.ResponseWriter, req *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "pong\n")
}

func startVMHandler(w http.ResponseWriter, req *http.Request) {
	var reqBody models.StartVMRequest
	if err := json.NewDecoder(req.Body).Decode(&reqBody); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}

	inst, ok := config.C.Proxmox[reqBody.Cluster]
	if !ok {
		http.Error(w, "unknown cluster", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(req.Context(), 15*time.Second)
	defer cancel()

	err := startVM(ctx, inst.APIURL, inst.APITokenID, inst.APITokenSecret, reqBody.Node, reqBody.VMID)
	if err != nil {
		resp := models.APIResponse{Success: false, Error: err.Error()}
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(resp)
		return
	}

	json.NewEncoder(w).Encode(models.APIResponse{Success: true})
}

func startVM(ctx context.Context, apiURL, tokenID, tokenSecret, node string, vmID int) error {
	url := fmt.Sprintf("%s/nodes/%s/qemu/%d/status/start", apiURL, node, vmID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Authorization", fmt.Sprintf("PVEAPIToken=%s=%s", tokenID, tokenSecret))
	req.Header.Set("Accept", "application/json")

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true,
		},
	}

	client := &http.Client{
		Transport: tr,
		Timeout:   10 * time.Second,
	}
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

func methodHandler(method string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		if req.Method != method {
			w.Header().Set("Allow", method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			fmt.Fprintf(w, "method %s is not allowed\n", req.Method)
			return
		}
		h(w, req)
	}
}

func main() {
	config.Init()
	http.HandleFunc("/ping", methodHandler("GET", pingHandler))
	http.HandleFunc("/start-vm", methodHandler("POST", startVMHandler))
	http.ListenAndServe(":"+config.C.Port, nil)
}
