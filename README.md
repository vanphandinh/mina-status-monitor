# mina-status-monitor
Tool for monitoring your mina daemon when your node stuck in the old blocks and stop snark worker for block producing.

# Environments
+ `SNARK_ADDRESS` - snark worker address
+ `SNARK_FEE` - snark worker fee (mina)
+ `TIMEZONE` - log timezone

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
