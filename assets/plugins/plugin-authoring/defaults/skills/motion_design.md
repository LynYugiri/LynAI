# 动效设计

当用户要求给页面/组件加动画、动效、过渡、微交互，或评审既有动效时使用。本 skill 是构建技能：把一个"想要动起来"的请求变成能通过严格评审的实现。它不审计整个代码库，只回答"这一个动画该怎么做"。

操作姿态：你是资深设计工程师，基准是"每个动画都要能回答：为什么动、为什么这么快、为什么用这条曲线"。写出来就要经得起评审。

## 决策框架（动手前按顺序回答）

### 1. 该不该动？

| 使用频率 | 决策 |
| --- | --- |
| 每天 100+ 次（快捷键、命令面板开关） | **永远不动**。动画让高频操作感觉慢、延迟、与动作脱节 |
| 每天几十次（hover、列表导航） | 去掉或大幅削减 |
| 偶尔（弹窗、抽屉、toast） | 标准动画 |
| 罕见/首次（引导、反馈表单、庆祝） | 可以加愉悦感 |

键盘触发的操作一律不加动画。Raycast 没有开合动画——对每天用几百次的东西，那才是最优体验。

### 2. 动效目的是什么？

合法目的：空间一致性（toast 从同方向进出，让滑动关闭直觉成立）、状态指示（按钮形态变化显示状态）、解释（营销动画演示功能）、反馈（按钮按下微缩，确认界面听到了你）、防止突兀（元素无过渡地出现/消失像坏了）。

如果目的只是"好看"且用户会经常看到，不动。

### 3. 用什么缓动？

决策树：

- 元素在进入或退出？→ **ease-out**（先快后慢，感觉响应快）。**UI 动画永远不用 ease-in**——开头慢让界面感觉迟钝；同样的 300ms，ease-in 的 dropdown 比 ease-out 感觉更慢，因为它延迟了用户盯得最紧的初始移动。
- 在屏幕上移动/变形？→ **ease-in-out**（自然加减速）。
- hover/颜色变化？→ **ease**。
- 恒定运动（跑马灯、进度条）？→ **linear**。

内置 CSS 缓动太弱，用自定义曲线：

```css
--ease-out: cubic-bezier(0.23, 1, 0.32, 1);      /* 强 ease-out，UI 交互 */
--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1);  /* 强 ease-in-out，屏幕内移动 */
--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1);   /* iOS 式抽屉曲线 */
```

不要从零造曲线，从 easing 曲线参考站找更强的标准变体。

### 4. 多快？

| 元素 | 时长 |
| --- | --- |
| 按钮按压反馈 | 100–160ms |
| Tooltip、小 popover | 125–200ms |
| Dropdown、select | 150–250ms |
| Modal、抽屉 | 200–500ms |
| 营销/解释动画 | 可以更长 |

**UI 动画保持在 300ms 以内**：180ms 的 dropdown 比 400ms 的感觉更灵敏；转得快的 spinner 让加载感觉更快（加载时间不变，感知变了）。感知速度与实际速度同样重要，缓动会放大它：200ms 的 ease-out 比 200ms 的 ease-in 感觉更快，因为用户立刻看到了移动。

## Spring 弹簧动画

比时长动画更自然，因为它模拟物理——没有固定时长，按物理参数收敛。

**什么时候用**：带动量的拖拽、需要"活着"感的元素（如灵动岛式）、可能被中途打断的手势、装饰性鼠标跟随。

**配置**（Apple 方式，推荐，易推理）：

```js
{ type: "spring", duration: 0.5, bounce: 0.2 }
```

传统物理参数（更多控制）：`{ type: "spring", mass: 1, stiffness: 100, damping: 10 }`。

bounce 保持克制（0.1–0.3），多数 UI 语境下避免弹跳；留给拖拽关闭和 playful 交互。

**可中断性优势**：弹簧被中断时保持速度继续——CSS 动画和 keyframes 会从零重启。点击展开项后立刻按 Esc，弹簧动画会从当前位置平滑逆转。这就是弹簧适合"用户可能中途改变主意的手势"的原因。

鼠标跟随类的视觉变化直接绑鼠标位置会显得假（没有惯性），用弹簧插值（如 stiffness 100 / damping 10）。注意这种动画是装饰性的；如果对象是银行 app 里的功能图表，不动更好——知道装饰何时加分、何时减分。

## 组件动效原则

### 按钮必须感觉有响应

任何可按压元素加 `:active` 微缩，瞬间反馈：

```css
.button { transition: transform 160ms ease-out; }
.button:active { transform: scale(0.97); }
```

幅度 0.95–0.98，微妙即可。

### 永远不从 scale(0) 开始动画

现实中没有东西从"完全不存在"出现。从 `scale(0.9)` 以上开始 + opacity 组合——即使初始形状几乎不可见，入场也更自然（像瘪掉但仍有形状的气球）。

### Popover 要从触发源生长

默认 `transform-origin: center` 对几乎所有 popover 都是错的；**modal 例外**（modal 不锚定触发源，保持 center）。单个差异用户注意不到，但聚合起来，看不见的细节会变成看得见的整体质感。

### Tooltip：首次延迟，后续即时

初次悬停要延迟防止误触；一旦有一个 tooltip 打开，相邻 tooltip 悬停即时显示、无动画（`transition-duration: 0ms`）。整体工具栏因此感觉更快。

### 可中断 UI 用 CSS transition 而非 keyframes

transition 可被中途打断和重定向，keyframes 从零重启。任何可能被快速触发的交互（连续加 toast、快速切换状态）都用 transition。

### 用 blur 遮瑕不完美的过渡

两个状态交叉淡化怎么调都别扭时，过渡中加轻微 `filter: blur(2px)`：没有 blur 时用户看到新旧两个对象重叠，blur 把它们融成一个连续变化。配合按钮按压 scale 使用更佳。blur 保持在 20px 以内（重 blur 开销大，Safari 尤甚）。

### 用 @starting-style 做入场动画

现代 CSS 无需 JS 的入场方案：

```css
.toast {
  opacity: 1;
  transform: translateY(0);
  transition: opacity 400ms ease, transform 400ms ease;
  @starting-style { opacity: 0; transform: translateY(16px); }
}
```

## transform 与 clip-path 技巧

- `translateY(50%)` 的百分比相对元素自身高度（不是父级）——这是很多位移动画写错尺寸的根源。
- `scale()` 缩放整个子树，包括子元素；只想缩放背景时单独处理。
- 3D transform（`rotateX`/`translateZ` + `perspective`）做纵深；`transform-origin` 决定一切旋转缩放的锚点。
- clip-path 形态动画：`inset()` 展开/收起；tab 切换用 clip-path 做完美颜色过渡；按住删除（hold-to-delete）用 `inset(0 0 0 round)` 从左到右填充；滚动图像揭示、对比滑块（before/after）都是经典模式。

## 手势与拖拽

- **动量消散**：不要强制拖过阈值才关闭。算速度 `|dragDistance| / elapsedTime`，超过约 0.11 就关闭——快速轻拂应该足够。
- **边界阻尼**：拖过自然边界时越拖移动越少（现实里物体不会突然停住，先减速）。
- **指针捕获**：拖拽开始后元素捕获所有 pointer 事件，指针移出元素边界也不中断。
- **多点触控保护**：初次拖拽开始后忽略新增触点，否则换手指会让元素跳到新位置。

## 滚动与页面级动效

- 视差、scrub、pinning 只服务叙事（营销页、演示页），产品界面不用。
- stagger（错峰入场）克制：一屏最多一组编排，别让每个元素排队出场。
- 入场动画只演一次，返回不重播；页面切换动画服务于空间一致性。
- 一切动效尊重 `prefers-reduced-motion`：动效超过简单状态反馈时，必须提供降级（减少位移、时长、去除视差）。

## 性能与实现

- 只动画 `transform`、`opacity`、`filter`（合成层属性），不动 `width`/`height`/`top`/`left`/layout 属性（触发重排）。
- `will-change` 克制使用（提前提升层会占内存，用完移除）。
- LynAI 功能页跑在移动端 WebView：预算按低端机算——同屏动效层数受限、blur/backdrop-filter 谨慎、大图位移动画降级为透明度过渡。
- 需要弹簧动画时优先用 Motion（原 Framer Motion）等成熟库，不要手写物理循环；纯 CSS 可完成的就用 transition。

## 成功 phase

```text
animation_justified
easing_selected
duration_set
implementation_written
reduced_motion_honored
```
