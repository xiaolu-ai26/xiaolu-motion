---
name: xiaolu-motion
description: Director workflow and reusable motion-graphics shot library for turning a talking-head or screen-recording video into a polished, packaged short-form edit — style selection, storyboard previews, effect shots, and a QA gate before final render. Use when editing or packaging a talking-head/voiceover video for short-form platforms (Xiaohongshu, Douyin, Shorts, Reels): cutting silence, adding kinetic captions and motion graphics, picking a visual style, or running a pixel-level QA pass before delivery.
---

# xiaolu-motion — 口播视频剪辑与包装 Skill

给任何创作者用的口播视频剪辑包装系统。输入一份逐字稿/分镜想法和一段真人口播或录屏素材,输出一条经过 QA 门禁的短视频成片。核心思路:**代码即分镜**——用 JSON 分镜描述画面,浏览器(headless Chrome + WebGL2)渲染透明动效层,ffmpeg 分层合成到底片上,Apple Vision 做像素级把关。不做可视化剪辑台,Agent 直接读文字、写分镜、出成片。

引擎、组件、渲染器和 QA 门禁已经是这个仓库的一部分(`engine/` `components/` `render/` `qa/` `timeline/`),这份 SKILL 说的是**用它们的工作流和固定规则**,不是又一份 API 文档——API 细节见各目录自己的代码注释和 `README.md`。

## 先决条件

只在 macOS 上完整可用(Apple Vision 做人脸/文字/卡片检测,`swiftc` 编译探针)。完整环境要求见仓库 `README.md`;缺字体先跑 `scripts/get_fonts.sh`。

## 四步流程

每一步做完都要拿给用户确认,得到明确点头才进下一步——不要因为"下一步逻辑上肯定要做"就抢跑,尤其是风格和分镜这两步,返工成本远高于多问一句。

### 第一步:确认选题

拿到逐字稿或选题想法后,先用一两句话复述你理解的核心信息和目标平台/画幅(小红书常见 3:4 或 9:16),让用户确认你没理解错,再往下走。如果逐字稿还没有词级时间码,先跑 ASR(`timeline/words.py` 的思路:整段转写 → 词级时间戳 → 存成 `words.json`,分镜里的时间点都可以用 `{"text": "…"}` 词锚代替绝对秒数,省得手数帧)。

### 第二步:画面风格 —— 先出风格样图,用户选完再往下

不要在没有风格共识的情况下直接出分镜。做法:
1. 看 `styles/` 目录下已有的风格包(见下文"怎么用风格包"),或者从 `library/` 里几条演示成片的风格截图找感觉。
2. 挑 2-3 个候选风格,每个用 `render/` 渲染一张静态样张(同一句文案、同一个组件,只换 `style` 字段),拼成一张对比图,或者直接甩给用户几张风格截图。
3. 用户选定风格(或要求混搭/微调令牌)之后再进入分镜阶段。没有明确回应之前,不要预设一个风格就往下写分镜——风格决定了后面所有令牌引用的颜色和字体,返工时几乎要重写每一镜。

### 第三步:分镜样帧 —— 先出关键帧,确认了再出全片

1. 按逐字稿写分镜 JSON(schema 见 `timeline/SCHEMA.md`;写法参考 `library/` 里任意一条现成分镜的 README)。挑几个关键镜头(通常是开场钩子 + 1-2 个代表性中段镜头 + 结尾),只渲染这几帧的静态样张——本引擎自己的分镜用 `python3 -m render stills RESOLVED --times 1.0 2.5 --out-dir DIR`(不用等全片渲染完);更复杂的分镜排版/多帧总览板参考 `library/_shared/storyboard-frames/`(渲染关键帧 PNG + 拼总览联系表的参考实现,含如何用它出"样图给用户选"的具体命令)。
2. 把样帧发给用户确认构图、字号、颜色、镜头节奏。用户觉得不对就改分镜参数重出样帧,不要跳过这一步直接渲染全片——渲染全片是这四步里最贵的一步,提前在样帧阶段挑错比事后重渲便宜得多。
3. 样帧通过后才进入第四步。

### 第四步:剪辑出片 —— 自检不过就重做,不带着已知问题交付

1. 先跑一遍"删停顿"(见下文),再决定是否整体提速。
2. 渲染:先出**低清全片**(参考本仓库既有的 540p 草稿惯例)给用户确认剪辑点、字幕时机、镜头顺序;确认没问题再出高清成片。低清阶段发现的问题(漏字、卡点不对、某镜太快看不清)在这一步改,不要等高清渲染完才发现。
3. 高清成片出来后跑 QA 门禁(`qa.check` 用于本引擎分镜,`qa.pixel_qa` 用于任意成片,见下文清单)。**QA 不过就是没做完,不是"差不多能用"**——回到分镜或剪辑点修,再重新出片、重新跑 QA,直到干净通过。不要把 `final.QA_FAILED.mp4` 当成交付物。
4. 交付前确认成片来源清楚:哪一版分镜、哪一版剪辑点列表、跑了哪次 QA 报告,方便用户回溯。
5. 把多个镜头/多条素材总装成一条成片(字幕烧录、插入既有成片、混音)时,`library/_shared/video20-a0-pipeline/` 是一个真实项目的参考实现——不是通用工具,但能看清楚这几步具体怎么接在一起;它的 README 标了哪些是那条视频专属、换项目要改哪些参数。

## 固定规则

这些规则是这套系统的设计前提,不是可选建议——分镜怎么写、组件怎么调参都要服从它们。

- **纸条字幕**:字幕做成"贴在画面上的纸条"观感(见 `library/` 的纸条字幕相关条目 / `a0lib.py` 的 `strip_geometry`/`strip_image`),不是无背景纯文字描边——纯文字字幕在复杂背景上可读性差,是这套系统明确要绕开的做法。
- **重点词放大配音效**:念到关键词时该词短暂放大/加高亮底,同时给一个轻的 pop 音效强调(`components/kinetic_keyword.js` 或 `library/` 里对应的纸质版机制,音效走 `audio/xlaudio` 的 `pop_soft`/`pop` 类音色),不要指望文字动效自己就够抓注意力。
- **人物不消失**:任何一镜切进全屏图形/图表/文档卡时,真人画面不能整个被盖住消失——收进右下角小画框(PiP,见"右下人像框"组件),让观众始终能看到人在讲。只有极短的转场镜头(≤ 若干帧的全屏遮罩转场,如 `token_cut`)例外。
- **不压脸、不压嘴**:任何图形/字幕/卡片都不能压在人脸框上,尤其是嘴部区域(脸框下三分之一)——这是 QA 门禁的硬规则(`face_cover`/`mouth_cover`),不是事后靠 QA 兜底,写分镜时就该避开人脸大概的屏幕位置。
- **平台名/品牌名可配置**:分镜、组件参数里出现的平台名称、产品名、品牌色不要硬编码,做成参数或令牌,换一个创作者/换一个产品就能整体替换,不用逐镜改字符串。
- **无人段 ≤ 3 秒**:任何连续的"画面里完全没有真人出现"的片段(纯图形转场、纯素材插入)不要超过 3 秒——太长会让观众觉得视频"跑题"或素材注水,这也是"人物不消失"规则的时长上限版本。

## 剪辑技术

### 删停顿(`scripts/pause_cuts.py`)

只剪静音、不剪内容。用法:

```bash
python3 scripts/pause_cuts.py detect --words words.json --video clip.mp4 \
  [--protect protect.json] -o cuts.json          # 找切点,写剪点表 JSON
python3 scripts/pause_cuts.py apply cuts.json --video clip.mp4 -o clip.cut.mp4   # 应用切点
```

- `--words` 是本仓库已有的 `timeline/words.py` 词级时间码格式(`{"words":[{"w","s","e"}, ...]}`)。
- `--protect` 是可选的保护区间列表(`[{"start","end","why"?}]`)——分镜里组件自己的入场/出场窗口、SFX 音效窗口都可以从分镜/组件参数里读出来,拼成这份文件传进去;绝不在这些区间内切。
- 默认规则:句中停顿(非结尾)长于 0.25s 的收短到约 0.15s,句末(依上一个词是否以 `。？！.!?` 结尾判断)收短到约 0.22s;每个切点在词起音前后各留 0.07/0.08s 安全带;给了 `--fps`(或 `--video` 自动探测到的帧率)时切点吸附到帧边界。
- 切点必须验证:`detect` 会对候选切点做人声能量(RMS/峰值 dBFS)检查,从响的一侧收缩直到低于 `--silence-db`(默认 -66dBFS)才落定,查不到足够安静的子区间就跳过、记进输出的 `skipped` 里,不会咬字。
- `apply` 用同一组切点同时剪画面和声音(音画对得上):画面在切点硬切(不做画面交叉淡化,会重影),声音在每个切点做等功率交叉淡化(`--crossfade-ms`,默认 12ms,落在 10-15ms 区间)。
- 一条视频生产管线自己的动画窗口表如果比一份手写的 `--protect` 文件更复杂(比如按分镜里每个组件动态算保护区间),参考 `library/_shared/video20-a0-pipeline/` 里更完整的项目专属实现。

### 可选整体提速(`scripts/speed.py`,约 1.1×)

```bash
python3 scripts/speed.py --video clip.cut.mp4 --speed 1.1 -o clip.fast.mp4
python3 scripts/speed.py --video clip.cut.mp4 --speed 1.1 --bgm bed.mp3 --bgm-gain-db -14 -o clip.fast.mp4
```

- 画面:`setpts=PTS/speed` 原始帧率丢帧,不插帧——动作观感不变,只是变快。
- 人声:ffmpeg `rubberband` 滤镜变速(`pitch=1` 保持音高),没有 `rubberband` 时退回 `atempo`(会打印警告,音高保持没有 rubberband 干净)。
- BGM(`--bgm`,可选):按自己的原速铺在提速后的新时长下面,不跟人声一起拉伸——跟着拉伸会和 BGM 自己的卡点对不上。这里只做简单的裁剪/循环+淡入淡出+增益混音,不是响度匹配的母带;要做贴合人声的闪避混音,把这个脚本产出的提速人声传给 `audio/xlaudio`(见 `audio/README.md`)。

## 性能与稳定性

跑这套系统需要同时喂饱 headless Chrome 渲染、ffmpeg 编码和 Apple Vision 探测,三者都吃 CPU/GPU/内存,同一台机器上多个任务/多个 Agent 会话并发很容易把内存挤爆。以下规则是踩过坑之后定下来的:

- **`scripts/with_heavy_lock.py`**:所有重任务(视频编码、Vision 探测、headless Chrome 渲染)一律用它包起来跑:
  ```bash
  python3 scripts/with_heavy_lock.py -- ffmpeg -i in.mp4 ... out.mp4
  python3 scripts/with_heavy_lock.py -- python3 -m qa.pixel_qa video.mp4 --out-dir out/
  ```
  它保证全机同一时间最多两个重任务在跑(两把 `flock` 文件锁),新任务要等系统空闲内存 ≥ 35% 才启动,运行中空闲内存跌破 12% 会先 `SIGTERM` 再 `SIGKILL` 掉子任务,防止一个任务把机器压垮连累其他任务。默认按 `<repo>/.cache/locks` 记锁,想跨多个 checkout 共享同一把锁就设 `XM_LOCK_DIR` 环境变量。
- **每任务 4 线程预算**:并行渲染 worker 数、ffmpeg `-threads` 都按"这台机器的核数 ÷ 4"这类预算规划,不要单个任务就把所有核吃满——同一时间可能有另一个重任务在排队(见上一条的并发上限是 2,不是 1)。
- **产物先写 `.partial` 再改名**:任何耗时的渲染/编码都先写到 `xxx.mp4.partial`,成功后再 `os.rename()`/`mv` 成最终文件名。这样即使中途被 `with_heavy_lock` 的内存告急机制杀掉,也不会有一个看起来完整、实际截断的文件被误当成交付物。
- **`ffmpeg -ss` 连读必须加 `-fps_mode passthrough`**:凡是先 `-ss` 定位再用 `select='eq(n,…)'` 挑帧的场景(逐帧抽样、按帧号取图),必须加 `-fps_mode passthrough`,否则 ffmpeg 为了维持恒定帧率会重新插值/复制时间戳,抽出来的帧号和实际内容对不上。参考本仓库 `qa/pixel_qa.py`/`qa/check.py` 里 `decode_frames()`/`grab_frames()` 的写法。
- **原始帧编码要标 BT.709 tv**:任何用纯色/测试图生成的"底片"或中间态视频,编码时都要显式标 `-color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv`(参考 `qa/alpha_selftest.py` 的 `ffmpeg_composite()`),否则合成器和 QA 探针拿到的色彩空间标记跟实际不一致,颜色对比检查会失真。
- **Apple Vision 探测必须分块处理,防内存泄漏**:一次探测调用不要让 `AVAssetReader` 从头顺序解码一整段长视频——按位置分段(而不是按"想要的帧数量"分段:稀疏采样时后者不能限制实际解码范围),每段用 `--start-frame` 让探针从接近目标的位置起读,每帧处理包在 `autoreleasepool` 里及时释放临时对象,每个子进程只处理一段就退出、由进程退出兜底回收内存。`qa/vision.py` + `qa/vision_probe.swift` 已经是这么实现的(2026-09-27 修过一次真实的内存泄漏:旧版一次探测调用在长视频上把 16GB 内存的机器压垮,新版同等测试峰值内存 &lt;250MB)——新写探测代码照这个模式来,不要退回"一次性把所有想要的帧丢给一个进程"的写法。

## 交付节奏:先低清、后高清

出片顺序固定是:低清全片(草稿分辨率,例如 540p)→ 用户确认剪辑点/字幕/节奏没问题 → 高清成片 → QA 门禁。跳过低清直接出高清,一旦剪辑点或分镜有问题就是重新渲染一整条高清成片的成本;低清阶段的渲染时间通常是高清的一个零头。

## QA 门禁清单

成片必须干净通过下面这些检查才算完成(任何一条命中都是门禁失败,不是警告):

- `face_cover` / `mouth_cover`:图形或字幕压住人脸框 / 嘴部区域(脸框下三分之一)。
- `caption_band` / `caption_misplaced`:非字幕内容占了字幕带(画面高 74–86%),或字幕跑到了字幕带以外。
- `top_persistent`:同一段文字长时间(≥ 80% 采样、≥ 10 秒)霸占画面顶部,像是遗留的调试信息或忘记退场的组件。
- `empty_card`:卡片类图形主体大半空白(≥ 一个阈值比例),像是内容没画上去。
- `overlap`:两段文字互压,文字骑在卡片边缘上,或卡片之间部分重叠。
- `safe_zone` / `min_font`(用引擎自身分镜跑 `qa.check` 时才有):图形出了安全区,或字号小于该画幅档位的最小可读字号。
- `transition_cover`:转场类组件在其中点时刻没有完全遮盖画面——转场中点通常用来藏底片的剪切点,没遮全就穿帮。

对着这套引擎自己的分镜跑 `python3 -m qa.check resolved.json --out-dir DIR`;对任意成片(包括不是用这套引擎渲染的素材)跑 `python3 -m qa.pixel_qa video.mp4 --start 0 --end N --srt captions.srt --out-dir DIR`。两者都会在 `DIR` 里留下 JSON 报告和问题帧的标注截图,报告里 `"gate": "FAIL"` 时把 `violations` 列表里每一条对应回分镜或剪辑点去改,不要只看截图猜。

## 怎么用镜头库(`library/`)

`library/` 是一批可直接参考/复用的具体动效实现,按 `LIBRARY.md` 的分组浏览(视频20 全部镜头 / 三条演示的代表效果 / 一部创意短片的场景 / 全局组件 / 待重建)。每条目录下:

- `preview.mp4` + `thumb.jpg`——先看效果像不像你要的,不用跑代码就能判断。
- `src/`——实现代码,大多是从真实项目里原样摘出来的参考实现,不是重新设计的"标准范例"。多个镜头共享的运行时/基础库统一放在 `library/_shared/<name>/`,各镜头的 README 会写清楚依赖哪个共享目录——先看共享目录自己的 README 再看具体镜头,单独复制某个 `src/` 文件不一定能独立跑起来。
- `README.md`——效果说明、来源、依赖、已知限制(比如某个效果引用了一个没有一起打包的外部素材,或者代码里还留着这条视频专属的文案/参数,不是纯粹通用逻辑)。

用法:先在 `LIBRARY.md` 里挑效果,读对应 `README.md` 确认依赖和限制,把 `src/` 里的绘制逻辑当参考移植进你自己的分镜/组件里(参数名字、坐标写死的地方通常需要按你的画幅重新量一遍,不要直接假设 1080 宽的写死数值适用于所有画幅)。同一个概念如果库里有两种视觉语言的实现(比如"关键词弹出"同时有 `components/kinetic_keyword.js` 的科技感版本和某条视频纸质手绘版本的实现),两个都看一遍再选,不要默认较新或较复杂的那个就是"对的"版本——这是风格取舍,不是正确性问题。

## 怎么用风格包(`styles/`)

风格是一个独立于代码的令牌包(`styles/*.json`):颜色、字体角色、动效节奏参数、后期强度全部在令牌里,组件代码只通过 `@accent`、`type.keyword` 这类角色名取值,换风格只换令牌文件,不改任何组件代码。写法:

- `styles/base.json` 是模板,列出所有组件会用到的键,取中性黑白值,不直接使用。
- 新风格用 `"extends": "base"`(或继承另一个已有风格)只覆盖要改的键,`render/common.py` 的 `load_style()` 会按继承链深合并。
- 现有风格包:`coldlight`(冷光,取自创意短片《在我开口之前》前半段)、`paperwhite`(纸白)、`scrapbook`(拼贴手账,取自 vlog 演示)、`kepu-explainer`(科普讲解,取自 kepu 演示)、`paper-handdrawn`(纸本手绘,取自 faceless 演示)——分镜里 `"style": "scrapbook"` 这样直接引用文件名(不带 `.json`)。
- 字体默认用可分发的开源字体(思源黑/宋、霞鹜文楷等,见 `fonts/SOURCES.md`),本机没装时退回系统字体,并在渲染报告里标记为"不可分发"——发布前确认最终用的字体角色都跑过 `scripts/get_fonts.sh` 或系统里确实装了对应字体,不要带着"不可分发"标记的成片去交付。

## 自定义 IP 开场(`components/ip_intro.js`)

固定开场组件(自我介绍句配大头贴+封面卡)默认打包的是占位素材,不是真人资产——换成你自己的:

1. 把你自己的照片处理成蓝底/纯色底的表情卡,跑 `python3 components/ip_intro/tools/cutout.py <你的蓝底图> components/ip_intro/assets/stickers/<name>.png` 抠成透明大头贴,再在 `components/ip_intro/assets/manifest.json` 里登记。
2. 往期封面素材属于本机资产,默认不入库(`components/ip_intro/assets/covers/.gitignore`)——用 `python3 components/ip_intro/tools/prep_covers.py <你的配方 JSON>` 按自己的封面生成 `covers/` 目录,组件缺图时会画空白纸卡占位,不会报错。
3. 组件参数(`prefix`/`name`/`name_color`/`sub`/`sub_hi` 等,见 `components/ip_intro/README.md`)按你自己的名字、口号、品牌色改,不要留着默认值里的示例文案。

## 兼容性

这套 SKILL 按 Agent Skills 通用格式编写,不绑定具体 Agent 产品——在 Claude Code、Codex 等支持读取仓库内 `SKILL.md`/技能文件的 Agent 里都可以直接引用这份文档驱动工作流。
