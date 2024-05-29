#!/bin/bash

# 指定要搜索的镜像名称
image_name="nezha123/titan-edge"

echo "检查Docker......"
docker -v
# 检查 Docker 是否已经安装
if [ $? -eq  0 ];then
    echo "docker已安装！"
else
    # 尝试识别操作系统
    if [ -f /etc/os-release ]; then
        # 加载操作系统信息
        . /etc/os-release
		
        if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
            # 使用 apt 安装 Docker
            sudo apt-get update
            sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
			curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
			sudo add-apt-repository "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/ $(lsb_release -cs) stable"
			sudo apt-get update
			sudo apt-get install docker-ce docker-ce-cli containerd.io
			sudo systemctl start docker
        elif [ "$ID" = "centos" ] || [ "$ID" = "fedora" ]; then
            # 使用 yum 安装 Docker
            sudo yum install -y yum-utils device-mapper-persistent-data lvm2
			sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin
			sudo systemctl start docker
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

# 检查镜像是否拉取成功
if [ $? -ne 0 ]; then
  echo "Failed to pull Docker image: $image_name"
  exit 1
fi

# 提示用户输入id_code，并读取输入
echo "请输入身份码:"
read id_code

# 提示用户输入id_code，并读取输入
echo "请输入存储空间容量:"
read size

# 提示用户选择单开公网或五开非公网
echo "请选择单开（输入1，将使用公网IP）多开（输入容器数2-5）"
read container_num


# 修改存储空间
command_to_execute="titan-edge config set --storage-size $size"

# 绑定身份码
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

# 计算需要创建的额外容器数量
additional_container_count=$(($container_num - running_container_count))

# 检查是否需要创建额外的容器
if [ $additional_container_count -gt 0 ]; then
  echo "需创建 $additional_container_count 个容器"
  
  # 创建额外的容器
  for i in $(seq 1 $additional_container_count); do
    # 创建对应的文件夹
    mkdir -p ~/.titanedge$i
    
    # 运行容器
	if [ "$container_num" -eq 1 ]; then
      echo "docker run -d -v --network host ~/.titanedge$i:/root/.titanedge "$image_name"
    else
      # 运行容器
      docker run -d -v ~/.titanedge$i:/root/.titanedge "$image_name"
    fi
  done
else
  echo "容器都已开始运行"
fi

# 获取所有匹配的容器 ID
container_ids=$(docker ps -aqf ancestor="$image_name")

# 检查是否有匹配的容器
if [ -z "$container_ids" ]; then
  echo "没有找到对应容器！"
  exit 1
fi

sleep 5

# 循环遍历所有容器，并在每个容器中执行指定命令
for container_id in $container_ids; do
  # 输出正在处理的容器 ID
  echo "正在处理的容器: $container_id"
  
  # 进入容器并执行绑定身份码
  docker exec -it "$container_id" bash -c "$extra_command"
  
  # 进入容器并执行修改存储空间
  docker exec -it "$container_id" bash -c "$command_to_execute"
  
  # 输出空行以区分容器之间的输出
  echo ""
  
  # 更新容器的重启策略为 always
  docker update --restart=always "$container_id"
  
  # 重启容器
  docker restart "$container_id"
done
