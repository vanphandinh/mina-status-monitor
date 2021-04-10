# mina-status-monitor
Tool for monitoring your mina daemon when your node stuck in the old blocks and stop snark worker for block producing.

# Environments
+ `DISABLE_SNARK_WORKER` - disable/enable the snark worker, default: FALSE
+ `SNARK_ADDRESS` - snark worker address, default: B62qkiJuTwdJBARAPGAvStuEa37kZVZPyDrQoUCuM7WQUmZZydNBmTf
+ `SNARK_FEE` - snark worker fee (mina), default: 0.001
+ `TIMEZONE` - log timezone, default: Asia/Ho_Chi_Minh

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
