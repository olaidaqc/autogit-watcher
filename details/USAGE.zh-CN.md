# 使用方法（稳定版）

## 一次性准备（你现在这台机器）

1. 确保已登录 GitHub CLI：`gh auth status`
2. 安装开机自启（推荐）：运行 `C:\Users\11918\Desktop\claude\autogit\install-startup.ps1`

## 从零开始做一个新项目（最常用）

1. 进入：`C:\Users\11918\Desktop\claude\projects`
2. 新建一个文件夹（这就是仓库名）：例如 `my-project`
3. 等待 AutoGit 初始化：
   - 会自动 `git init`
   - 会自动生成 `.gitignore`（常见忽略规则）
   - 会自动首次 `commit`
   - 会自动在 GitHub 创建同名仓库并 `push`（默认私密）
4. 开始写代码：你在项目里新增/修改/删除文件，停下来约 20 秒后会自动提交并推送一次。

## 改名/删除你本地的项目文件夹会怎样？

### 改名 `projects` 下的第一层项目文件夹（例如 `my-project` -> `my-project-new`）

- 本地：文件夹名会改
- GitHub：会尝试把仓库也改名（`gh repo rename`）
- 本地 remote：会自动更新 `origin` 到新仓库名

前提：

- 这个项目文件夹里已经有 `.git`，并且 `origin` 是 GitHub
- 你有权限改名这个仓库

### 删除本地项目文件夹

- 本地：文件夹没了
- GitHub：仓库不会自动删除（避免误删）

如果你确定要删 GitHub 仓库，需要你手动删除（后面可以再加“自动删除”的功能，但默认不建议开）。

## 可调参数（环境变量）

- `AUTOGIT_PROJECTS_ROOT`
  - 默认：`C:\Users\11918\Desktop\claude\projects`
- `AUTOGIT_LOG_PATH`
  - 默认：`C:\Users\11918\Desktop\claude\autogit\autogit.log`
- `AUTOGIT_SKIP_REMOTE=1`
  - 不创建 GitHub 仓库，也不 push（只做本地 git）
- `AUTOGIT_REPO_VISIBILITY=private|public`
  - 默认 `private`
- `AUTOGIT_GIT_NAME` / `AUTOGIT_GIT_EMAIL`
  - 当你的 git 没配置身份时，AutoGit 会写入 repo-local 的默认值（不改全局）

