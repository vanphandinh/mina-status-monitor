# mina-status-monitor

Tool for monitoring your mina daemon when your node stuck in the old blocks, monitoring mina-sidecar when it is timeout and stop snark worker for block producing.

I assumed that:
+ The mina container name is `mina`
+ The mina-sidecar container name is `mina-sidecar`

If it's incorrect for you, please change it to similar above

# Environments

- `DISABLE_SIDECAR` - disable/enable the mina sidecar monitor, default: FALSE
- `DISABLE_SNARK_WORKER` - disable/enable the snark worker stopper, default: TRUE
- `DISABLE_EXTERNAL_IP` - disable/enable external ip monitor, default: TRUE
- `SNARK_ADDRESS` - snark worker address, default: B62qkiJuTwdJBARAPGAvStuEa37kZVZPyDrQoUCuM7WQUmZZydNBmTf
- `SNARK_FEE` - snark worker fee (mina), default: 0.001
- `TIMEZONE` - log timezone, default: Asia/Ho_Chi_Minh

# Usages

1. Clone this repo & cd to the folder

```
git clone https://github.com/vanphandinh/mina-status-monitor.git && cd mina-status-monitor
```

2. Run docker container

```
docker-compose up -d
```

# Update the latest version

1. Cd to the repo and pull the update

```
cd mina-status-monitor && git pull
```

2. Update the latest version

```
docker-compose up -d --build && docker system prune -af
```
