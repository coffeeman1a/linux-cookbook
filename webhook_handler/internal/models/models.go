package models

type StartVMRequest struct {
	Cluster string `json:"cluster"`
	Node    string `json:"node"`
	VMID    int    `json:"vm_id"`
}

type APIResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}
