# fork-skill

面向新 Fork 的上游同步与二开隔离技能。

三条分支：

- `upstream/main`（或 `upstream/<上游默认分支>`）：origin 上的纯镜像，只允许快进。
- `dev`：正在进行的二开。
- `main`：对外发布与部署。只接收已经在 `dev` 验证过的结果。原先这支分支叫 `release`。

安装或导入时，以 `SKILL.md` 为技能入口。

统一导航在 [oceans777/skills](https://github.com/oceans777/skills)。
