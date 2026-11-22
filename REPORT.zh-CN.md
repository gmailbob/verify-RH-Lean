# 验证报告

> 本文为 [REPORT.md](REPORT.md) 的中文译本。如两者有出入，以英文版为准。

状态，2026-11-22：**所有步骤均已运行。第 0–8 步全部通过。第 9 步在 MIT 公布的导出文件上通过。**

## 结论

**我们的独立运行表明：<https://alpo.ge/remark.pdf> 所发布的 Lean 库，是对黎曼猜想（与 Mathlib
中的表述完全一致）以及狄利克雷 L 函数的广义黎曼猜想的完整、有效的机器验证证明。**

我们在与参考运行不同的硬件上（aarch64，而非 x86_64）从零重新构建了该库。我们从空环境出发，用
Lean 内核重新检查了每一条声明，这是参考运行跳过的一步。随后，我们又让另一个独立编写的内核接受了导出
的证明。所有检查均通过，源代码及其元程序中也没有任何绕过内核的途径。这一结果与
[Lean 和 Mathlib 社区的联合声明](https://leanprover-community.github.io/blog/posts/riemann-hypothesis/)
以及 <https://math.mit.edu/~drew/grh/> 公布的检查结果一致。

在我们的运行中，信任一个 Lean 证明的四项标准全部满足：

1. **命题是正确的。** `riemannHypothesis` 的类型是 `RiemannHypothesis`，即
   `Mathlib.NumberTheory.LSeries.RiemannZeta` 中 Mathlib 自己的定义，而不是复制品或改写。
   其内容是：ζ 的除平凡零点 −2, −4, … 之外的每个零点，实部都等于 1/2。四个 GRH 命题只使用
   Mathlib 的 `DirichletCharacter.LFunction` 和 `IsPrimitive`。全部五个命题与
   `scripts/audit/Reviewed.lean` 中经人工审阅的文本在语法上完全相同。
2. **库可以编译。** 用固定版本的 Lean v4.33.1 和 Mathlib，从经过哈希校验的归档构建：183,903 个任务中
   183,903 个完成，0 个错误。构建前后源代码逐字节相同。我们的编译文件中有 76,968 个（包括 `Main.olean`）
   与 MIT 的独立构建逐字节相同；其余 98,219 个恰好是 Lean 在其中嵌入了源文件绝对路径的文件。
3. **代码证明的正是这一命题。** 五个最终定理的类型恰好是审阅过的命题。它们只依赖三条标准公理：
   `propext`、`Classical.choice` 和 `Quot.sound`。没有 `sorry`，没有新公理，没有 `native_decide`，
   也没有 `unsafe`、`extern` 或 `implemented_by` 代码。项目的元程序中没有任何文件或进程 I/O 调用。
4. **证明是有效的。**
   - **Lean 内核**从空环境出发（`leanchecker --fresh Main`，13 小时），接受了这些定理所依赖的每一条
     声明，涵盖 Lean 核心库、整个 Mathlib 以及全部 175,187 个项目模块。
   - **con-leche** 是独立于 Lean 编写的内核，它接受了导出证明中的全部 1,468,418 条声明。在此之前的
     自检表明：它接受真实的导出文件，并拒绝被篡改的导出文件。

**这一结论所依赖的前提**，与任何 Lean 证明相同：
- **内核。** 两个独立实现结论一致。
- **Mathlib 中 ζ 与狄利克雷 L 函数的定义。** 它们经过了 Mathlib 的审核；社区声明特别指出，RH 的
  表述已由 Lean 和数论方面的专家仔细核查。
- **对约 40 行的 `Reviewed.lean` 的人工阅读。**

有一个环节我们没有亲自闭合：con-leche 检查的导出文件是 MIT 公布的文件（已对照其公布的两个哈希值
校验），而不是我们自己构建的导出。我们的构建与该文件的联系，来自逐文件的 `.olean` 比对。社区声明
提到，许多独立构建都复现出了同一个导出文件。导出我们自己的构建所需的内存超出了本机容量，详见第 9 步
一节。

这是对形式化证明的验证，而不是对其数学思想的审阅。关于这些思想位于何处的初步梳理，见下文“证明结构”。

**证据。** 本报告中每一项陈述所依据的日志和输出都在 [`evidence/`](evidence/) 中。其
[README](evidence/README.md) 说明了哪个文件支持哪项结论。

## 机器

AWS `c8gn.8xlarge`：Graviton4，32 个 vCPU（aarch64），61 GiB 内存 + 64 GiB 交换空间，2.0 TB xfs 根分区，
位于 EBS 卷（网络存储）上，Amazon Linux 2023。`JOBS=28`。详情见 `evidence/machine.txt`。

## 各步骤结果

每一步的完整日志在 `evidence/logs/` 中；各项结论对应的文件列在 `evidence/README.md` 中。

| 步骤 | 结果 | 说明 |
|---|---|---|
| 0 机器 | 通过 | 可用空间 1,993 GB。 |
| 1 工具链 | 通过 | `lean-4.33.1-linux_aarch64.tar.zst` 的 sha256 `f7353a8b…5f07` = 固定值 = GitHub 资源摘要；二进制报告的提交 `819816b2…` 即标签 `v4.33.1`。`leanchecker --fresh Init` 重放耗时 47 秒，占用 0.5 GB。 |
| 2 源代码 | 通过 | `remark.pdf`、全部 14 个分卷以及 `lean.tar.gz`（`9631b4f0…c7fc`，239,275,554 字节）均匹配。归档在 `lean/` 下包含 175,190 个普通文件（其中 175,187 个 `.lean`），没有链接和不安全路径。工具链固定版本、mathlib `0df444a3…` 以及全部 9 个清单版本均匹配。基线哈希列表的摘要：`859c80e3fe4912ad9e18ad359edbfdc62fb845ad340add30b5caa0fdc74d2ee1`。 |
| 3 扫描 | 通过 | 代码和注释中硬性失败标记的数量为零。元编程清单：见 README 的“Reading the scan”一节。 |
| 4 依赖 | 通过 | 1.5 分钟。全部 9 个依赖的检出均位于固定版本，没有修改，也没有意外的包。Mathlib 缓存（来自 `lakecache.blob.core.windows.net` 的 8,690 个文件）完整：全部 8,312 个 Mathlib 模块都有 `.olean`。Mathlib 的工具链文件为 v4.33.1；其他依赖声明 v4.33.0，但都用 v4.33.1 构建。`.lake` 为 7.6 GB。 |
| 5 构建 | **通过** | `Build completed successfully (183903 jobs)`，任务数与参考运行相同。0 个错误，0 个失败任务；全部 175,187 个项目模块均已构建，最后是 `Supplements.Kernels.MainTheoremsAll` 和 `Main`。时间：05:07:52–06:53:34 和 07:04:51–17:23:22 UTC，共 12 小时 04 分构建时间。期间因调高 `vm.max_map_count` 重启过一次（见 README 的要求一节），Lake 保留了已构建的 27,864 个模块。104,045 个任务报告了警告（489,061 行 `warning:`）；参考运行报告 460,321 条警告，计数单位未说明。`.lake` 为 1.2 TB；构建后剩余 709 GB 磁盘空间。内存峰值使用 31 GB；从未使用交换空间。 |
| 6 自检 | 通过 | 8 个正例和 10 个反例。 |
| 6 命题 | 通过 | 在构建之前、仅对照 Mathlib 运行，耗时 3 秒，占用 7.5 GB。`RiemannHypothesis` 是 Mathlib 的定义（模块 `Mathlib.NumberTheory.LSeries.RiemannZeta`）。全部 5 个命题与 `Reviewed.lean` 在语法上完全相同，且只使用 Mathlib/核心库常量（每个 35–40 个）。 |
| 6 完整审计 | **通过** | 49 秒，内存峰值 35 GB。在构建好的项目中：`RiemannHypothesis` 定义于 `Mathlib.NumberTheory.LSeries.RiemannZeta`；4 个项目命题定义于 `Statements`；全部 5 个与 `Reviewed.lean` 在语法上完全相同，且只使用 Mathlib/核心库常量。5 个定理定义于 `Main`，类型完全符合预期，且每个都只依赖 `propext`、`Classical.choice` 和 `Quot.sound`。 |
| 7 重放 | **通过** | `leanchecker --fresh --verbose Main` 退出码 0。从空环境出发，内核接受了 `Main` 所依赖的每一条声明：Lean 核心库、Mathlib（包括 CI 构建的缓存）以及全部项目模块。17:27:45 → 06:42:29 UTC：实际耗时 13 小时 14 分 44 秒，单核 CPU 时间 45,696 秒。RSS 峰值 48.5 GB，主要是基于文件的 `.olean` 页面；匿名内存峰值约 16 GB；从未使用交换空间。参考运行跳过了这一步。 |
| 8（构建前） | 通过 | 解压后的目录树与归档成员逐字节相同。 |
| 8（构建后） | **通过** | 构建之后，全部 175,190 个文件与归档成员以及第 2 步的基线逐字节相同（哈希列表摘要 `859c80e3…`）。 |
| 9 独立内核 | **在 MIT 的导出上通过**；未完成自己的导出 | 准备工作和自检通过。独立编写的内核 con-leche 接受了 MIT 公布的 `Main` 导出中的全部 1,468,418 条声明（两个公布的哈希值均已校验）。**我们自己的导出未完成**，因此未做哈希比对；它说明了什么、没有说明什么，见第 9 步一节。 |

## 命题审阅

- `Main.riemannHypothesis : RiemannHypothesis`。`Statements.lean` 没有定义 `RiemannHypothesis`，
  因此这个名字解析为 Mathlib 的定义。在固定的 mathlib 版本中，该定义为
  `∀ (s : ℂ) (_ : riemannZeta s = 0) (_ : ¬∃ n : ℕ, s = -2 * (n + 1)) (_ : s ≠ 1), s.re = 1 / 2`。
  这是标准的黎曼猜想；它只排除了平凡零点和极点。
- `Statements.lean` 中另外四个命题都很短，且只使用 Mathlib 的概念。它们断言，对每个模数 N 和每个
  狄利克雷特征 χ：当 Re s > 1/2 时 L(χ, s) 不为零（平凡特征的极点除外）；带状区域 0 < Re s < 1
  中的零点都在 Re s = 1/2 上；对本原 χ 同样成立。

## 第 9 步，独立内核：做了什么，说明了什么，没有说明什么

**准备工作和自检。**
- 已校验 Lean v4.36.0 的哈希值。
- `lean4export` 在 `15f6055e`（标签 v4.33.0）构建，con-leche 在 `cd2eceab`（master）构建，与 MIT
  运行所用的版本相同。
- con-leche 接受了几个 `Init` 定理的真实导出。它拒绝了一个被篡改的副本（其中一个定理的证明被换成了
  另一个定理的证明），报错 `type mismatch in theorem Nat.add_comm`。

**我们自己的导出：尝试过，未完成。**
- 带固定导出目标的 `lean4export Main` 于 2026-11-22 06:45 至 07:52 UTC 运行。在最初约 20 GB 中，写入
  速度约为 14 MB/s。
- 写到预计约 61.6 GB 中的 25.4 GB（41%）时，内存余量耗尽：
  - 导出程序自身的表已达到约 32 GB。
  - 它以随机顺序读取约 90 GB 的 `.olean` 数据。
  - 这些装不进 61 GiB 内存，于是 `.olean` 页面被换出，又从 EBS 磁盘重新读入。
- 一次 30 秒的采样显示：26,045 次主缺页，从磁盘读取 819 MiB，而进程只用了 1 秒 CPU，写出 23 MiB 的
  导出内容。
- 交换空间不是瓶颈：它一直保持在约 3.8 GB。
- 以低于 1 MB/s 的速度，预计还需约 13 小时。逐分钟的记录见
  `evidence/independent-kernel/own-export-memtrend.csv`。调大磁盘预读没有帮助。为节省时间，我们停止了
  导出，并决定不再完成它。
- **因此，我们没有自己构建的导出文件，也没有将其哈希与 MIT 的进行比对。**

**在 MIT 公布的导出上运行 con-leche（`EXPORT_SOURCE=mit`）。**
- 从 <https://math.mit.edu/~drew/grh/> 下载。该文件与 MIT 公布的两个哈希值都匹配：
  - 压缩文件 `61a8938a…`，7,699,933,588 字节：**匹配**；
  - 解压后 `5ea74b91…`，61,570,595,788 字节：**匹配**。
- con-leche 的结论：**`accepted 1468418 declarations (--verified)`**，退出码 0。声明数与 MIT 的运行
  相同。耗时 12 分 44 秒（从 EBS 解析 61.6 GB 文件用了 475 秒，32 个工作线程检查用了 286 秒）。RSS
  峰值 43.6 GiB，未使用交换空间。日志：`evidence/independent-kernel/con-leche-solution-mit.log`。

**这说明了：**
- 一个独立编写的内核，由我们在自己的机器上运行，接受了 MIT 作为其 `Main` 导出所公布的文件。这一点
  不再依赖 MIT 的日志。
- 我们的构建与 MIT 的构建一致。76,968 个 `.olean` 文件逐字节相同，包括 `Main.olean`。不同的 98,219
  个恰好是那些带有源文件路径的文件（见下文“他人的独立内核检查”）。

**这没有说明：**
- **该导出文件来自我们的构建。** 导出文件是如何产生的，我们依赖 MIT：即他们的构建和他们运行的
  `lean4export`；按他们自己的说明，这些运行在未沙箱化的机器上进行。公布的哈希值只证明我们检查的是他们
  公布的那个文件。
- 那 98,219 个带路径的 `.olean` 文件除路径外与 MIT 的相同。这一点是根据数量和 MIT 的解释推断的，
  并没有逐字节比较。
- 因此，对我们自己的构建而言，只有 Lean 内核检查过证明（第 5–7 步）。独立内核的结论是通过 `.olean`
  比对间接延伸到我们的构建的，而不是直接作用于它。

**要闭合这一缺口，** 请在容得下导出的机器上以默认模式运行第 9 步（导出你自己的构建）：内存 ≥128 GB，
最好使用本地 NVMe 存储而不是网络存储。届时导出预计需要约 1–2 小时（这是估计，未经实测）。如果其
sha256 等于 `5ea74b91…`，独立内核的结论便逐字节地适用于你的构建；如果不同，con-leche 会直接检查你的
导出。

## 证明结构（探索性，非验证）

根据形式化命题及其连接方式阅读而得（`scripts/extra/ProofTree.lean`，然后是源文件）。我们没有检查其中
的数学。

- **顶层是经典部分。** RH 和临界带形式都由 `UpperTheory.EveryCharacter` 推出；后者断言：对每个狄利克雷
  特征 χ，当 Re s > 1/2 时 L(χ, s) ≠ 0。这与最终命题 `DirichletLNonvanishingRightOfHalf` 逐字相同。其中
  的归约（`Formalism.VW.rh_of_right`、`Claim.strip`、`Claim.prim_zero`、`Claim.prim_reflect`、
  `Formalism.VW.critLine`）都是标准的：函数方程、归约到本原特征，以及欧拉因子和 Γ 因子不为零。每个只有
  0–4 个项目依赖。
- **其余一切都汇入 `EveryCharacter`**，经由
  `UpperTheory.LiteratureTheorems.every_character_of_literature_of_vWin`。它的输入是：
  - **项目标注为“文献”的结果：**
    - `UpperTheory.GalStar.Row0b`：附着于 CM 域上 GL_a 的正则代数、极化尖自守表示的伽罗瓦表示，并具有
      局部-整体相容性。
    - GL_n 的局部朗兰兹对应。
    - 特征 0 中的奇点消解。
    - θ 积分匹配和“自交体积估计”。
  - **`UpperTheory.Top.VWin`：** 对每个本原特征 ψ、在窗口 [Y, Y²] 上的显式估计（常数 401），经由
    `automorphic_window_of_inputs`（“模性论证”“阈值论证”）和基变换证明。
- **新的数学必然位于：** 上述组合之中。下面的支配分析显示了哪一部分承载了证明的大部分。
- **这些“文献”结果是在项目内部证明的，而不是假设的。** 五个定理除三条标准公理外不使用任何公理。
  因此正确性并不取决于这些内部命题是否与其所命名的已发表定理一致，只取决于内核和 Mathlib 的定义。

### 证明的主体在哪里（支配分析）

方法：`scripts/extra/depgraph/`。它导出构建好的项目在声明层面的依赖图：1,905,921 条项目声明（其中
1,079,944 条为人工编写），以及 20,986,047 条边。该环境共有 186,200 个模块和 2,701,132 个常量，与 MIT
的审计日志中的总数相同。从根出发，它计算支配树。一条声明的**独占份额**是指*只*通过它才需要的全部内容。
与依赖锥的大小不同，这些份额互不重叠。下表的份额都是相对于 `riemannHypothesis` 的依赖锥：1,265,256 条
声明，其中 791,182 条为人工编写。其他最终定理的依赖锥基本相同。

| 声明 | 依赖锥 | 独占份额 |
|---|---|---|
| `UpperTheory.FinalTheorems.everyCharacter`（半平面定理） | 100% | 100%。其上的 RH 和带状区域形式只增加了少数几条声明。 |
| `UpperTheory.LiteratureTheorems.every_character_of_literature_of_vWin`（组合定理） | 83.7% | 66.5% |
| `UpperTheory.Lit.every_character_of_theta_integrals_local_matching` | 61.0% | **42.7%**，单个最大部分 |
| 其中的 `UpperTheory.Lit.nonempty_hyps_definite_side_of_closed_bound` | | 35.5% |
| `SelfIntersectionVolumeEstimates.topCovolSlim2_use_alt_alt`，经由 Moriwaki 大性 / Hilbert–Samuel / 塔体积 | | 6.3% |
| `UpperTheory.One.vwin_of_row`（`VWin` 窗口估计） | 21.9% | 7.2% |
| `UpperTheory.Gal.Int.galoisLocalGlobalStrong_recParameter`（`Row0b`，经由 θ 提升和几何实现得到的伽罗瓦表示） | 24.0% | 7.1% |
| `UpperTheory.Zero.LLC.recTExists`（局部朗兰兹输入） | 1.7% | 0.05% |
| `Formalism.VW.rh_of_every`（由半平面定理推出 RH） | 6 条声明 | 无 |
| `Claim.strip`、`Claim.zeta`（临界带形式） | 8 条和 10 条声明 | 无 |

仅从结构得出的解读：
- **经典归约非常小。** 由半平面定理推出 RH 和临界带命题只需要十来条声明。
- **θ 积分 / 局部匹配论证占主导。** 它独占 42.7%，其中大部分在为其“定号一侧”建立的假设之下。读者应当
  首先看这里。
- **`VWin` 和伽罗瓦表示输入各约占 7%。** 自交 / 体积估计约占 6%。
- **项目中约三分之一，即 640,665 条声明（其中 288,762 条为人工编写），不被五个最终定理中的任何一个
  使用。** 它们仍然被编译并经过内核检查。

运行时间：28 分钟。其中从冷缓存导入项目用 5.7 分钟，导出用 16 分钟（受 EBS 磁盘限制），自检用 6.5
分钟；分析本身只需几秒。RSS 峰值 54.7 GB，主要是缓存的 `.olean` 页面。完整报告见
`evidence/proof-structure/depgraph-report.txt`。

## 他人的独立内核检查，以及我们的构建与之的关系

Andrew Sutherland（MIT）在 <https://math.mit.edu/~drew/grh/> 公布了对同一归档的进一步检查（页面更新于
2026-11-21 12:55 UTC）。我们审阅了该页面及其日志；以下是他们的陈述，而非我们的运行：

- 两个独立编写的内核接受了完整的导出证明（`Main` 的 `lean4export` 导出，61,570,595,788 字节，sha256
  `5ea74b91…`）：**nanoda**（Rust 编写；退出码 0，80 线程用时 27 分 42 秒，峰值 89 GB）和 **con-leche**
  master `cd2eceab`（以 `--verified` 模式接受 1,468,418 条声明；64 线程用时 3 分 15 秒，峰值 47.8 GB）。
  两份日志都以退出码 0 结束。
- `con-leche --compare` 将全部五个定理与一个只导入 Mathlib 的挑战文件进行匹配，因此所检查的命题就是
  Mathlib 的命题。
- 逐模块运行 `leanchecker`：175,187 个中 175,187 个通过。逐模块运行 `lean4lean`：175,187 个通过；其中
  5 个因 `decide +kernel` 计算需要调高步数上限。
- 他们的环境中有 15 条公理，全部位于 `Init`。五个定理只使用 `propext`、`Classical.choice` 和
  `Quot.sound`。
- 当时，对导出文件运行 Lean 默认内核和偏执（paranoid）内核，以及端到端的 `lake comparator`，仍在
  进行中。
- 他们页面上自己说明的注意事项：他们通过直接调用 `lean` 编译每个文件，而不是通过 `lake build`，且在
  未沙箱化的云机器上运行。

**除嵌入路径外，我们的构建与 MIT 的构建一致。** 我们的 `Main.olean`（在 aarch64 上通过 `lake build`
构建）的 sha256 为 `9146dfb4…`，与他们的完全相同。他们的页面没有说明所用的架构。对照他们全部 175,187 个
`.olean` 哈希的清单，我们有 76,968 个文件逐字节相同，98,219 个不同。每一个不同的文件都包含我们的源路径，
而相同的文件都不包含。Lean v4.33 会在保存的 linter 消息旁存放源文件的绝对路径；他们的页面报告的正是
76,968 个不含路径、98,219 个含路径的文件。因此，除嵌入路径外，我们独立的 `lake build` 复现了独立内核
所接受的那份导出所来自的构建。对带路径的文件而言，这一点是根据数量和 MIT 的解释推断的，并没有逐字节
比较。（`scripts/extra/compare_olean_manifest.py`；以空闲优先级运行 7.5 分钟。）我们完整的 `.olean`
哈希列表见 `evidence/build-match/project-oleans.sha256.zst`，格式与 MIT 的相同，任何人都可以重做这一
比对，或与自己的构建比较，而无需构建。

## 对参考运行所作陈述的观察

来源：<https://proveriemannhypothesis.github.io/>。

- 它的分卷哈希、归档哈希、`lean-toolchain` 和 `lake-manifest.json` 与我们的一致。
- 磁盘：它在 16:15 UTC 的遥测样本显示根磁盘为 1.08 TB，而其摘要却说在 2 TiB 磁盘上使用了 1.17 TiB。
  它的 `archive/storage-at-migration.json` 解释了这一点：11 月 21 日 07:28 UTC 时，运行数据位于一块
  2 TiB 的磁盘上，已用 1.28 TB；也就是说，它在构建之后迁移到了更大的磁盘上。我们 1.2 TB 的 `.lake`
  与此相符。
- 它的 `result.json` 与我们的一致：183,903 / 183,903 个构建任务，0 个失败。公理：只有
  `Classical.choice`、`Quot.sound` 和 `propext`。175,187 个源文件未被修改。工具链 sha256 为
  `890afd18…`，即官方的 x86_64 资源（已固定在 `config.sh` 中）。内核重放：“skipped … Omitted at user
  request”。
- 它的 `memory-peak.json` 报告的“构建内存峰值”为 210.0 GiB（225,485,783,040 字节）。该值等于 cgroup
  的上限，包含文件缓存，且只来自一次采样（首次 = 峰值 = 末次 = 16:34:44 UTC），因此无法说明 Lean 实际
  需要多少内存。唯一有用的数据是 16:15 UTC 的 `machine-sample.json` 快照：48 线程时，243.8 GiB 中使用了
  36.0 GiB，此时构建约进行了 40 分钟。这只是快照，而非峰值。两者都与参考站点所显示的一致。
