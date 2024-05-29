#!/bin/bash

# 指定要搜索的镜像名称
image_name="nezha123/titan-edge"

echo "检查Docker..."
docker -v
if [ $? -eq 0 ]; then
    echo "docker已安装！"
else
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
            curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/ $(lsb_release -cs) stable"
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        elif [ "$ID" = "centos" ] || [ "$ID" = "fedora" ]; then
            sudo yum install -y yum-utils device-mapper-persistent-data lvm2
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
        else
            echo "抱歉该脚本暂不支持你的操作系统版本，请手动安装docker."
            exit 1
        fi
    else
        echo "抱歉没识别到你的操作系统呢，请手动安装docker."
        exit 1
    fi
fi

# 启动 Docker 服务
sudo systemctl start docker

# 拉取镜像
echo "Pulling Docker image: $image_name"
docker pull "$image_name"

if [ $? -ne 0 ]; then
    echo "Failed to pull Docker image: $image_name"
    exit 1
fi

# 提示用户输入信息
echo "请输入身份码:"
read id_code
echo "请输入存储空间容量:"
read size
echo "请选择单开（输入1，将使用公网IP）多开（输入容器数2-5）"
read container_num

# 修改存储空间命令
command_to_execute="titan-edge config set --storage-size $size"
# 绑定身份码命令
extra_command="titan-edge bind --hash=$id_code https://api-test1.container1.titannet.io/api/v2/device/binding"

# 等待镜像完全拉取
echo "Waiting for Docker image to be fully pulled..."
docker image inspect "$image_name" &> /dev/null
while [ $? -ne 0 ]; do
    echo -n "."
    sleep 1
    docker image inspect "$image_name" &> /dev/null
done
echo "Docker 镜像已拉取完毕"

# 获取当前正在运行的该镜像的容器数量
running_container_count=$(docker ps -qf ancestor="$image_name" | wc -l)
additional_container_count=$((container_num - running_container_count))

if [ $additional_container_count -gt 0 ]; then
    echo "需创建 $additional_container_count 个容器"
    for i in $(seq 1 $additional_container_count); do
        mkdir -p ~/.titanedge$i
        if [ "$container_num" -eq 1 ]; then
            docker run -d --network host -v ~/.titanedge$i:/root/.titanedge "$image_name"
        else
            docker run -d -v ~/.titanedge$i:/root/.titanedge "$image_name"
        fi
    done
else
    echo "容器都已开始运行"
fi

container_ids=$(docker ps -aqf ancestor="$image_name")
if [ -z "$container_ids" ]; then
    echo "没有找到对应容器！"
    exit 1
fi

sleep 5

for container_id in $container_ids; do
    echo "正在处理的容器: $container_id"
    docker exec -it "$container_id" bash -c "$extra_command"
    docker exec -it "$container_id" bash -c "$command_to_execute"
    echo ""
    docker update --restart=always "$container_id"
    docker restart "$container_id"
done
