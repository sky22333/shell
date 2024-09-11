### 卸载站点及环境
- 删除站点文件
```
sudo rm -r /var/www/
```

- 停止
```
sudo systemctl stop caddy apache2 mariadb
```

- 禁用开机自启
```
sudo systemctl disable caddy apache2 mariadb
```

- 卸载软件包
```
sudo apt remove --purge caddy apache2 php* mariadb-server mariadb-client -y
```

- 清理残留配置和依赖
```
sudo apt autoremove -y
```
