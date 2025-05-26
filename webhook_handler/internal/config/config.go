package config

import (
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type ProxmoxInstance struct {
	Name           string
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
	godotenv.Load()
	proxmoxNames := strings.Split(os.Getenv("PROXMOX_LIST"), ",")
	cfg := Config{Proxmox: make(map[string]ProxmoxInstance, len(proxmoxNames))}

	cfg.Port = os.Getenv("PORT")

	for _, name := range proxmoxNames {
		upper := strings.ToUpper(name)
		inst := ProxmoxInstance{
			Name:           name,
			APIURL:         os.Getenv("PROXMOX_" + upper + "_URL"),
			APITokenID:     os.Getenv("PROXMOX_" + upper + "_TOKEN_ID"),
			APITokenSecret: os.Getenv("PROXMOX_" + upper + "_TOKEN_SECRET"),
		}
		cfg.Proxmox[name] = inst
	}

	C = cfg
}
