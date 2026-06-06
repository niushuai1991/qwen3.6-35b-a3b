# WSL2 注意事项

## `docker run --gpus all` 报 GPU 找不到

WSL2 的 nvidia-ctk 生成的 CDI spec 可能引用错误驱动路径。重新生成：

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
# 验证
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

正常会列出你的 GPU。
