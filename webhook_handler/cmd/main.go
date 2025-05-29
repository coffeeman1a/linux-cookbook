package main

import (
	"log"
	"net/http"
	"webhook-handler/internal/config"
	"webhook-handler/internal/handlers"
)

func main() {
	config.Init()
	http.HandleFunc("/ping", handlers.MethodHandler("GET", handlers.PingHandler))
	http.HandleFunc("/start-vm", handlers.MethodHandler("POST", handlers.StartVMHandler))
	log.Printf("[INFO] Server started on port: %s", config.C.Port)
	if err := http.ListenAndServe(":"+config.C.Port, nil); err != nil {
		log.Fatalf("[FATAL] ListenAndServe failed: %v", err)
	}
}
