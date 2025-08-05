#!/bin/bash
# Augment2API 项目构建脚本
# 服务端口: 27080
# 支持多架构构建 (linux/amd64, linux/arm64)
PROJECT_NAME=augment2api
PROJECT_DESC="Augment API 中间件服务"

echo '当前项目名称为:' "$PROJECT_NAME" - "$PROJECT_DESC"

# 从命令行参数中获取密码
password=$1

# 如果命令行参数没有提供密码，尝试从环境变量获取
if [ -z "$password" ] && [ -n "$DOCKER_PASSWORD" ]; then
  password=$DOCKER_PASSWORD
  echo "从环境变量DOCKER_PASSWORD中获取密码"
fi

echo '当前工作目录为:' "$PWD"

# 获取开始时间
start_time=$(date +%s)

version=v1.0.0-$(date '+%Y%m%d%H%M%S')
echo '待构建的镜像版本为:' "$version"

registry=registry.cn-wulanchabu.aliyuncs.com
imagePro=registry.cn-wulanchabu.aliyuncs.com/ydy-lowcode/$PROJECT_NAME

# 检测操作系统类型
os_type=$(uname -s)
echo "检测到操作系统: $os_type"

case $os_type in
    "Darwin")
        echo "Mac 系统检测到，使用 Docker Buildx 进行多架构构建..."
        use_buildx=true
        platforms="linux/amd64,linux/arm64"
        build_desc="多架构镜像 (linux/amd64, linux/arm64)"
        ;;
    "Linux"|"MINGW"*|"CYGWIN"*)
        echo "非 Mac 系统检测到，使用传统 Docker 构建 (x64)..."
        use_buildx=false
        platforms="linux/amd64"
        build_desc="单架构镜像 (linux/amd64)"
        ;;
    *)
        echo "警告: 未识别的操作系统 $os_type，默认使用传统构建方式"
        use_buildx=false
        platforms="linux/amd64"
        build_desc="单架构镜像 (linux/amd64)"
        ;;
esac

if [ "$use_buildx" = true ]; then
    # Mac 系统 - 使用 Buildx 多架构构建
    echo "检查 Docker Buildx 环境..."
    if ! docker buildx version >/dev/null 2>&1; then
        echo "错误: Docker Buildx 不可用，请确保 Docker Desktop 支持 buildx 功能"
        exit 1
    fi

    # 检查或创建buildx构建器
    builder_name="multiarch-builder"
    if ! docker buildx inspect $builder_name >/dev/null 2>&1; then
        echo "创建多架构构建器: $builder_name"
        docker buildx create --name $builder_name --use --platform $platforms
    else
        echo "使用已存在的构建器: $builder_name"
        docker buildx use $builder_name
    fi

    # 启动构建器（如果未运行）
    echo "确保构建器正在运行..."
    docker buildx inspect --bootstrap

    # 开始多架构镜像构建
    echo "开始构建 $build_desc..."
    if [ -n "$password" ]; then
        echo "检测到密码，将构建并推送镜像。"
        # 登录到镜像仓库
        docker login --username=candycloud $registry --password=$password
        
        # 构建并推送多架构镜像
        docker buildx build \
            --platform $platforms \
            --push \
            -t $imagePro:$version \
            -t $imagePro:latest \
            .
        
        echo "$build_desc 构建并推送完成。"
    else
        echo "未提供密码，仅构建镜像到本地缓存。"
        # 仅构建，不推送
        docker buildx build \
            --platform $platforms \
            -t $imagePro:$version \
            -t $imagePro:latest \
            .
        
        echo "$build_desc 构建完成（仅本地缓存）。"
    fi

    # 显示构建的镜像信息
    echo "构建的镜像信息:"
    docker buildx imagetools inspect $imagePro:$version 2>/dev/null || echo "镜像信息获取失败（可能未推送到仓库）"

else
    # 非 Mac 系统 - 使用传统 Docker 构建
    echo "开始构建 $build_desc..."
    
    if [ -n "$password" ]; then
        echo "检测到密码，将构建并推送镜像。"
        # 登录到镜像仓库
        docker login --username=candycloud $registry --password=$password
        
        # 构建镜像
        docker build --platform $platforms -f Dockerfile -t $imagePro:$version -t $imagePro:latest .
        echo "镜像构建完成。"
        
        # 推送镜像
        docker push $imagePro:$version
        docker push $imagePro:latest
        echo "镜像推送完成。"
        
        # 清理本地镜像
        docker rmi $imagePro:$version
        docker rmi $imagePro:latest
        echo "本地镜像清理完成。"
    else
        echo "未提供密码，仅构建镜像到本地。"
        # 仅构建镜像
        docker build --platform $platforms -f Dockerfile -t $imagePro:$version -t $imagePro:latest .
        echo "$build_desc 构建完成。"
    fi

    # 显示本地镜像信息
    if [ -z "$password" ]; then
        echo "本地镜像信息:"
        docker images | grep $PROJECT_NAME | head -5
    fi
fi

# 获取结束时间
end_time=$(date +%s)

# 计算时间差
elapsed_time=$((end_time - start_time))

echo ""
echo "==================== 构建完成 ===================="
echo "项目名称: $PROJECT_NAME"
echo "镜像标签: $imagePro:$version"
echo "镜像标签: $imagePro:latest"
echo "构建模式: $build_desc"
echo "操作系统: $os_type"
echo "耗时: $elapsed_time 秒"
echo "=================================================="

# 清理提示
if [ "$use_buildx" = true ]; then
    if [ -n "$password" ]; then
        echo ""
        echo "注意: 推送的镜像会占用仓库空间。"
        echo "如需清理本地构建缓存，可运行: docker buildx prune"
    else
        echo ""
        echo "提示: 镜像已构建到本地缓存中。"
        echo "如需推送，请提供密码重新运行脚本。"
        echo "清理本地缓存: docker buildx prune"
    fi
else
    if [ -n "$password" ]; then
        echo ""
        echo "注意: 镜像已推送到仓库。"
    else
        echo ""
        echo "提示: 镜像已构建到本地。"
        echo "如需推送，请提供密码重新运行脚本。"
        echo "清理本地镜像: docker rmi $imagePro:$version $imagePro:latest"
    fi
fi
