# 验证报告

> 本文为 [REPORT.md](REPORT.md) 的中文译本。如两者有出入，以英文版为准。

状态，2026-11-26：**所有步骤均已运行，全部通过。**

对象：<https://github.com/lsernau/grh-lean> 的可读版本（`grh/`），提交
`72fead102f663d5c7a407964a13dc0cf9d977207`。它是 Levent Alpöge 的 Lean 证明的一个更短的改写。
我们此前对原始的 1700 万行库的验证保存在分支
[`original`](https://github.com/gmailbob/verify-RH-Lean/tree/original) 上。

## 结论

**我们的独立运行表明：这个 Lean 库是对黎曼猜想（与 Mathlib 中的表述完全一致）以及狄利克雷 L 函数的
广义黎曼猜想的完整、有效的机器验证证明。**

我们从零下载了该证明，并用经过哈希校验的官方 Lean 版本进行构建。随后，Lean 内核从空环境出发重新检查
了每一条声明。最后，三个独立编写的内核各自接受了我们自己构建的导出。所有检查均通过；源代码中没有
元程序，也没有任何绕过内核的途径。

在我们的运行中，信任一个 Lean 证明的四项标准全部满足：

1. **命题是正确的。** `riemannHypothesis` 的类型是 `RiemannHypothesis`，即
   `Mathlib.NumberTheory.LSeries.RiemannZeta` 中 Mathlib 自己的定义，而不是复制品或改写。
   其内容是：ζ 的除平凡零点 −2, −4, … 之外的每个零点，实部都等于 1/2。四个 GRH 命题只使用
   Mathlib 的 `DirichletCharacter.LFunction` 和 `IsPrimitive`。全部五个命题与
   `scripts/audit/Reviewed.lean` 中经人工审阅的文本在语法上完全相同。
2. **库可以编译。** 位于固定提交的全新克隆，其内容与固定的 sha256 摘要一致，用固定版本的
   Lean v4.35.0 和 Mathlib 构建：9,852 个任务中 9,852 个完成，0 个错误，全部 803 个项目模块。
   构建前后源代码逐字节相同。
3. **代码证明的正是这一命题。** 五个最终定理的类型恰好是审阅过的命题。它们只依赖三条标准公理：
   `propext`、`Classical.choice` 和 `Quot.sound`。代码中没有 `sorry`，没有新公理，没有
   `native_decide`，也没有 `unsafe`、`extern` 或 `implemented_by`。其中完全没有元程序。
4. **证明是有效的。**
   - **Lean 内核**从空环境出发（`leanchecker --fresh Main`），接受了这些定理所依赖的每一条声明：
     Lean 核心库、整个 Mathlib 以及本项目。
   - **con-leche**、**con-ron** 和 **nanoda** 这三个独立于 Lean 编写的内核，各自接受了我们自己
     构建的导出。我们给 nanoda 提供了只含三条标准公理的允许列表，它没有发现其他公理。在此之前的
     自检表明：它们各自都接受真实的导出，并拒绝被篡改的导出。

**这一结论所依赖的前提**，与任何 Lean 证明相同：
- **内核。** 四个实现结论一致。三个独立内核是与 Lean 本身同一个官方发行版中附带的二进制文件，
  因此它们共用这一个二进制来源。
- **Mathlib 中 ζ 与狄利克雷 L 函数的定义。**
- **对约 40 行的 `Reviewed.lean` 的人工阅读。**

这是对形式化证明的验证，而不是对其数学思想的审阅。上游对其自身的检查也是这样说的：
“No mathematician has read it through, and no paper comes with it.”（没有数学家通读过它，也没有随附
论文。）

**证据。** 本报告中每一项陈述所依据的日志和输出都在 [`evidence/`](evidence/) 中。其
[README](evidence/README.md) 说明了哪个文件支持哪项结论。

## 机器

AWS `c8gn.8xlarge`：Graviton4，32 个 vCPU（aarch64），61 GiB 内存，无交换空间，2.0 TB xfs 根分区，
位于 EBS 卷（网络存储）上，Amazon Linux 2023。`JOBS=28`。详情见 `evidence/machine.txt`。

## 各步骤结果

每一步的完整日志在 `evidence/logs/` 中；各项结论对应的文件列在 `evidence/README.md` 中。

| 步骤 | 结果 | 说明 |
|---|---|---|
| 0 机器 | 通过 | 可用空间 2,058 GB；61 GiB 内存供 28 个构建任务使用。 |
| 1 工具链 | 通过 | `lean-4.35.0-linux_aarch64.tar.zst` 的 sha256 `c8f0f8a3…b028` = 固定值 = GitHub 资源摘要。二进制报告的提交 `eb6cafb7…` 即标签 `v4.35.0`。 |
| 2 源代码 | 通过 | 全新克隆位于固定的提交。`grh/` 包含 818 个普通文件：`src/` 下 803 个 `.lean` 文件、`Challenge.lean`、`scripts/PrintAxioms.lean` 以及另外 13 个文件。内容摘要 `ab5bc5e431464ed94f4073ba8b4215481208465d341f702397d81a10b03c25f6`。另一份单独制作的克隆给出相同的摘要。工具链固定版本、Mathlib `56a00585…` 以及全部 9 个清单版本均匹配。 |
| 3 扫描 | 通过 | 代码中硬性失败标记的数量为零。没有元程序、宏或记号定义。清单：见 README 的“Reading the scan”一节。 |
| 4 依赖 | 通过 | 48 秒。全部 9 个依赖的检出均位于固定版本，没有修改，也没有意外的包。Mathlib 缓存（9,031 个文件）完整：全部 8,625 个 Mathlib 模块都有 `.olean`。 |
| 5 构建 | **通过** | `Build completed successfully (9852 jobs)`，耗时 12 分 28 秒。0 个错误，0 个失败任务；全部 803 个项目模块均已构建。10 行警告：9 条关于 Mathlib 模块系统的提示和 1 条 linter 消息。 |
| 6 自检 | 通过 | 8 个正例和 10 个反例，在 Lean v4.35.0 上。 |
| 6 命题 | 通过 | 在构建之前、仅对照 Mathlib 运行。`RiemannHypothesis` 是 Mathlib 的定义（模块 `Mathlib.NumberTheory.LSeries.RiemannZeta`）。全部 5 个命题与 `Reviewed.lean` 在语法上完全相同，且只使用 Mathlib/核心库常量（每个 35–40 个）。 |
| 6 完整审计 | **通过** | 3 秒。在构建好的项目中：4 个项目命题定义于 `Statements`，全部 5 个与 `Reviewed.lean` 在语法上完全相同。5 个定理定义于 `Main`，类型完全符合预期，且每个都只依赖 `propext`、`Classical.choice` 和 `Quot.sound`。 |
| 7 重放 | **通过** | `leanchecker --fresh --verbose Main` 在单核上运行 46 分钟后以退出码 0 结束。从空环境出发，内核接受了 `Main` 所依赖的每一条声明：Lean 核心库、Mathlib（包括 CI 构建的缓存）以及全部项目模块。 |
| 8（构建前） | 通过 | 目录树与固定的内容摘要以及第 2 步的基线一致。 |
| 8（构建后） | **通过** | 构建之后，目录树仍与固定的摘要和基线一致；克隆位于固定的提交，没有被修改的文件。 |
| 9 自检 | 通过 | con-leche、con-ron 和 nanoda 各自接受了几个核心库定理的真实导出，并拒绝了被篡改的副本。nanoda 还拒绝了使用允许列表之外公理的导出。 |
| 9 导出 | **通过** | 以五个定理为目标运行 `leanexport Main`：4,486,595,522 字节，sha256 `a28b40e7e90aa8477b01294d0afce119d1756d42b582c17a009f85694493396e`。 |
| 9 检查 | **通过** | 三个独立内核都接受了该导出。con-leche：`accepted 216567 declarations (--verified)`。con-ron：`accepted 216567 declarations (--verified)`。nanoda：`Checked 222117 declarations with no typechecker errors`，且没有允许列表之外的公理。数量不同是因为各工具统计声明的单位不同。 |

关于第 9 步日志的两点说明（该日志包含这一步的每次运行）：
- 第一次尝试中，con-leche 和 con-ron 因为我们传入了一个它们不接受的命令行选项而立即停止（退出码 3，
  属于用法错误，不是对证明的判定）。现在自检使用与正式运行相同的选项，这类错误几秒钟内就会暴露。
- nanoda 在其结论旁打印了 `1 pretty printer errors: "Unable to print axioms"`。这来自它的格式化
  输出功能，我们并不使用；它没有报告任何类型检查错误。

## 测量结果

上游报告在 12 核、24 GB 内存上构建需要一到两小时。在本机上：

| 步骤 | 实际耗时 | 内存峰值 | 说明 |
|---|---|---|---|
| 第 0–4 步以及第 6、9 步的构建前阶段 | 从空工作目录开始 76 秒 | | 含下载 |
| 5 构建，28 个任务 | 12 分 28 秒 | 整机使用 22.7 GiB；最大进程 RSS 10.8 GiB | CPU 时间 4.9 核·小时 |
| 6 完整审计 | 3 秒 | RSS 8.7 GiB | |
| 7 内核重放，单核 | 46 分 0 秒 | RSS 10.9 GiB | CPU 时间 45.5 分钟；与第 9 步的第一次运行同时进行 |
| 9 导出，单核 | 3 分 38 秒 | RSS 12.6 GiB | 写出 4.49 GB |
| 9 con-leche，32 线程 | 1 分 39 秒 | RSS 5.1 GiB | |
| 9 con-ron，32 线程 | 1 分 0 秒 | RSS 7.6 GiB | |
| 9 nanoda，32 线程 | 1 分 39 秒 | RSS 12.8 GiB | 单线程时：23 分 40 秒，5.6 GiB |

- **总计：** 各步骤依次运行约 70 分钟。第 9 步可以与第 7 步同时运行，这样约为一小时。
- **磁盘：** 结束时工作目录占用 23 GB。工具链 3 GB；Mathlib、其他包和本项目的构建共 15 GB（本项目自身的
  构建为 7.5 GB）；导出文件 4.5 GB。
- **内存映射：** 一个导入整个项目的 Lean 进程持有 55,794 个映射，构建期间观察到的最大值为 55,767。
  Linux 默认的 `vm.max_map_count` 为 65,530，因此按这一测量，默认值是够用的。本机设为 1,048,576，
  所以我们并没有在默认值下实际运行。
- “使用的内存”不含文件缓存；RSS 数字包含映射的 `.olean` 页面，这些页面由各进程共享。

## 命题审阅

`grh/src/Statements.lean` 中的四个定义与原始库的命题文件相同，`Main.lean` 证明的五个定理名称也相同。

- `Main.riemannHypothesis : RiemannHypothesis`。`Statements.lean` 没有定义 `RiemannHypothesis`，
  因此这个名字解析为 Mathlib 的定义。在固定的 Mathlib 版本中，该定义为
  `∀ (s : ℂ) (_ : riemannZeta s = 0) (_ : ¬∃ n : ℕ, s = -2 * (n + 1)) (_ : s ≠ 1), s.re = 1 / 2`。
  这是标准的黎曼猜想；它只排除了平凡零点和极点。
- 另外四个命题都很短，且只使用 Mathlib 的概念。它们断言，对每个模数 N 和每个狄利克雷特征 χ：
  当 Re s > 1/2 时 L(χ, s) 不为零（平凡特征的极点除外）；带状区域 0 < Re s < 1 中的零点都在
  Re s = 1/2 上；对本原 χ 同样成立。

## 证明结构（探索性，非验证）

根据构建好的项目在声明层面的依赖图得出（`scripts/extra/depgraph/`）。我们没有检查其中的数学。

- 项目共有 64,456 条声明，其中 26,524 条为人工编写，依赖边 713,214 条。
- `riemannHypothesis` 需要其中的 49,815 条（77.3%），包括人工编写声明中的 25,127 条（94.7%）。其他
  最终定理需要的集合基本相同。
- 一条声明的**独占份额**是指*只*通过它才需要的全部内容。这些份额互不重叠。下表的份额都是相对于
  `riemannHypothesis` 的 49,815 条声明。

| 声明 | 模块 | 独占份额 |
|---|---|---|
| `New.grh`，半平面形式的定理 | `New.Reduction.OneSidedBound` | 99.98% |
| `New.eventually_primeRemainder_le_rpow`，单侧界 | `New.Reduction.OneSidedBound` | 99.6% |
| `New.star_inequality`，主不等式 | `New.Reduction.MainInequality` | 89.9% |
| `New.Data.integral_forms_long` | `New.Determinant.Twist.LongForms` | 46.5% |
| `New.exists_isRegularFamily` | `New.Congruences.FitTwistsExist` | 32.3% |
| `New.GaloisRep.sphericalCompat_of_odd` | `Lib.GaloisRep.Main.OddRank` | 13.9% |
| `New.Data.exists_err_gaugeLe_compositeLift` | `New.UpperBound.Divisibility.LocalDivisibility` | 3.5% |
| `New.Data.seesaw_identity` | `New.UpperBound.Seesaw.SeesawIdentity` | 2.9% |

仅从结构得出的解读：
- **一切都经过同一条链。** RH 由半平面定理 `New.grh` 经 `New.zeta_zeros_on_line` 推出，后者需要
  7 条声明。`New.grh` 由一个单侧界推出，单侧界又由主不等式推出，而主不等式承载了证明的 90%。这与上游
  对主不等式和半平面定理所在位置的描述一致。
- **在主不等式之下，** 最大的单个分支是 `integral_forms_long`，占 46.5%，其中大部分是一族正则扭曲的
  存在性（32.3%）。另有 29.6% 分散在 6,847 个较小的分支中。
- **按领域看，** RH 所需的声明分布很广：最大的几个领域是 `New.Spanning`（11%）、`New.UpperBound`
  （8%）和 `Lib.Weil`（8%）。
- 有 1,397 条人工编写的声明没有被 `riemannHypothesis` 使用。

完整报告见 `evidence/proof-structure/depgraph-report.txt`。导出并分析该依赖图用了 15 秒。

## 与原始库那次运行的不同之处

- **来源。** 是一个 git 仓库，而不是分卷归档。第 2 步重新克隆，检查提交，并检查覆盖每个文件的
  sha256 摘要，因此内容不只依赖 git。
- **规模。** 803 个模块，而不是 175,187 个；构建 12 分钟，而不是 12 小时；内核重放 46 分钟，而不是
  13 小时。
- **元程序。** 这里没有。原始库使用了不经繁饰器类型检查就赋值证明项的自定义策略，以及一条复制定理的
  命令。
- **独立内核。** Lean v4.35.0 自带导出程序和三个独立编写的检查器。第 9 步用这些二进制文件检查我们
  自己构建的导出。对原始库，我们的机器无法导出 62 GB 的证明，因此只能检查他人公布的导出。

## 上游对其自身检查的说明

摘自 `grh/README.md`，并附上我们的运行所补充的内容：

| 上游的说法 | 我们的运行 |
|---|---|
| 每个文件都能无错误、无 `sorry` 地编译 | 已复现，在另一台机器上 |
| 五个定理只依赖 `propext`、`Classical.choice` 和 `Quot.sound` | 已复现，通过我们自己的审计和 nanoda 的允许列表 |
| 导出被 nanoda、con-leche 和 con-ron 接受 | 已复现，使用我们自己构建的导出 |
| Comparator v4.35.0 对照 `Challenge.lean` 接受了这些证明 | 未运行；我们的第 6 步改为将命题与我们自己审阅的文本进行比较 |
| “No mathematician has read it through, and no paper comes with it” | 不变：我们只验证了形式化证明 |

我们的运行还对整个环境做了一次全新的内核重放（第 7 步）。
