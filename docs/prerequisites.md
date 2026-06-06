# 前置条件

所有模型部署的通用前置要求。

---

## Docker + Compose

要求 `docker >= 24.0` 且 compose v2（`docker compose version` 可查）。

## NVIDIA Container Toolkit

按 [官方指南](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) 安装 `nvidia-container-toolkit`，然后：

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

## CDI 配置

CDI spec 生成与 WSL2 注意事项见 [wsl2-notes.md](./wsl2-notes.md)。
