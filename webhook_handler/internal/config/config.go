package config

import (
	"log"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type ProxmoxInstance struct {
	Name           string
	PUSHGATEWAY    string
	APIURL         string
	APITokenID     string
	APITokenSecret string
}

type Config struct {
	Port    string
	Proxmox map[string]ProxmoxInstance
}

var C Config

func Init() {
	log.SetOutput(os.Stderr)
	// Добавляем префикс и метки времени в формате YYYY/MM/DD hh:mm:ss
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	log.SetPrefix("[WEBHOOK-HANDLER] ")
	godotenv.Load()
	proxmoxNames := strings.Split(os.Getenv("PROXMOX_LIST"), ",")
	cfg := Config{Proxmox: make(map[string]ProxmoxInstance, len(proxmoxNames))}

	cfg.Port = os.Getenv("PORT")

	for _, name := range proxmoxNames {
		upper := strings.ToUpper(name)
		inst := ProxmoxInstance{
			Name:           name,
			APIURL:         os.Getenv("PROXMOX_" + upper + "_URL"),
			PUSHGATEWAY:    os.Getenv("PUSHGATEWAY_" + upper + "_URL"),
			APITokenID:     os.Getenv("PROXMOX_" + upper + "_TOKEN_ID"),
			APITokenSecret: os.Getenv("PROXMOX_" + upper + "_TOKEN_SECRET"),
		}
		cfg.Proxmox[name] = inst
	}

	log.Printf("Proxmox instances defined: %s", proxmoxNames)

	C = cfg
}
