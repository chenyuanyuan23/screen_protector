#!/bin/bash

# 同步官方仓库脚本
# upstream: git@github.com:prongbang/screen_protector.git
# origin: git@chenyuanyuan23:chenyuanyuan23/screen_protector.git

set -e

echo "==> 获取官方仓库最新代码..."
git fetch upstream

echo ""
echo "==> 官方仓库分支列表:"
git branch -r | grep upstream

echo ""
echo "==> 当前分支:"
git branch --show-current

echo ""
read -p "是否合并 upstream/master 到当前分支? (y/n): " confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    echo ""
    echo "==> 正在合并 upstream/master..."
    git merge upstream/master
    echo ""
    echo "==> 合并完成!"
else
    echo ""
    echo "==> 已取消合并"
fi
