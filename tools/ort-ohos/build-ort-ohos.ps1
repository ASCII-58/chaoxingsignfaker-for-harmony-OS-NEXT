# 交叉编译裁剪版 ONNX Runtime 1.16.3（arm64-v8a, ohos musl），供本项目 libonnxruntime.so 使用。
# 用法: pwsh build-ort-ohos.ps1 [-Phase update|reduce|build|all]
#
# 前置条件（本机路径，换机器请调整）:
#   ORT 源码   E:\deveco\ort-1.16.3-src
#     git clone --depth 1 --branch v1.16.3 https://github.com/microsoft/onnxruntime.git <dir>
#     git -C <dir> submodule update --init --depth 1 cmake/external/onnx
#   host protoc  E:\deveco\ort-build-tools\bin\protoc.exe  (protobuf v21.12 win64 release)
#   OHOS NDK     D:\OtherApp\DevEco Studio\sdk\default\openharmony\native（提供 cmake/ninja/clang/sysroot）
#   Python 3.12（build.py / reduce_op_kernels.py）
#
# 产物: <buildDir>\MinSizeRel\libonnxruntime.so（需 llvm-strip 后替换
#       entry/src/main/cpp/libs/arm64-v8a/libonnxruntime.so）
# 白名单: captcha_ops.config（YOLO11n fp16 模型 opset 19 的 16 个算子）
param([ValidateSet('update', 'reduce', 'build', 'all')][string]$Phase = 'all')

$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1' # ORT python scripts open files with locale encoding on Windows (GBK); force UTF-8
$ortRoot  = 'E:\deveco\ort-1.16.3-src'
$buildDir = 'E:\deveco\ort-build-ohos'
$ndk      = 'D:\OtherApp\DevEco Studio\sdk\default\openharmony\native'
$cmake    = "$ndk\build-tools\cmake\bin\cmake.exe"
$ninja    = "$ndk\build-tools\cmake\bin\ninja.exe"
$protoc   = 'E:\deveco\ort-build-tools\bin\protoc.exe'
$opsCfg   = "$PSScriptRoot\captcha_ops.config"

$common = @(
  '--build_dir', $buildDir,
  '--config', 'MinSizeRel',
  '--cmake_generator', 'Ninja',
  '--cmake_path', $cmake,
  '--ctest_path', "$ndk\build-tools\cmake\bin\ctest.exe",
  '--skip_submodule_sync',
  '--parallel',
  '--build_shared_lib',
  '--skip_tests',
  # ohos.toolchain.cmake 传的 --gcc-toolchain 对 ohos triple 无效，clang 报
  # "argument unused"，被 ORT 的 -Werror 升级成错误；关掉 Werror 即可
  '--compile_no_warning_as_error',
  '--disable_contrib_ops',
  '--disable_ml_ops',
  '--disable_rtti',
  '--include_ops_by_config', $opsCfg,
  '--path_to_protoc_exe', $protoc,
  '--cmake_extra_defines',
    "CMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/ohos.toolchain.cmake",
    'OHOS_ARCH=arm64-v8a',
    'OHOS_PLATFORM=OHOS',
    "CMAKE_MAKE_PROGRAM=$ninja",
    'ORT_DISABLE_WERROR=ON',
    # OHOS 上 cpuinfo 不支持（CPUINFO_SUPPORTED_PLATFORM=0），其符号不会编出，
    # 链接必失败；关闭后 ORT 走 sysconf 回退
    'onnxruntime_ENABLE_CPUINFO=OFF',
    # 体积优化：MinSizeRel 默认 -Os，改成 -Oz；开 ThinLTO（工具链为 lld，支持）
    'CMAKE_C_FLAGS_MINSIZEREL=-Oz -DNDEBUG',
    'CMAKE_CXX_FLAGS_MINSIZEREL=-Oz -DNDEBUG',
    'onnxruntime_ENABLE_LTO=ON',
    # gitlab 提交归档 zip 字节不稳定，SHA1 校验必失败（ORT 已知问题）：
    # 手动下载解压后用本地源码目录绕过下载校验
    'FETCHCONTENT_SOURCE_DIR_EIGEN=E:/deveco/ort-deps/eigen-e7248b26a1ed53fa030c5c459f7ea095dfd276ac'
)

Set-Location $ortRoot

# Patch: 允许关闭 CMake 的 COMPILE_WARNING_AS_ERROR。ohos.toolchain.cmake 传的
# --gcc-toolchain 对 ohos triple 无效，clang 报 unused-command-line-argument 警告，
# 该属性（ORT cmake/CMakeLists.txt 对所有目标无条件 ON，由 CMake 注入 -Werror）
# 会把它升级成编译错误。幂等：只在未打补丁时替换。
$cl = "$ortRoot\cmake\CMakeLists.txt"
$txt = Get-Content $cl -Raw
if ($txt -notmatch 'ORT_DISABLE_WERROR') {
  $old = '    set_target_properties(${target_name} PROPERTIES COMPILE_WARNING_AS_ERROR ON)'
  $new = @'
    if (NOT ORT_DISABLE_WERROR)
      set_target_properties(${target_name} PROPERTIES COMPILE_WARNING_AS_ERROR ON)
    endif() # [chaoxing-patch: ORT_DISABLE_WERROR]
'@
  if (-not $txt.Contains($old)) { throw "patch anchor not found in $cl" }
  Set-Content -Path $cl -Value $txt.Replace($old, $new) -NoNewline -Encoding UTF8
  Write-Host "patched $cl (ORT_DISABLE_WERROR)"
}

# Patch: musl 没有 glibc 扩展 pthread_setaffinity_np（ohos musl 会命中
# ThreadMain 的亲和性分支）。本项目不用线程亲和性（且 OHOS 上 cpuinfo 不可用），
# 直接对该平台禁用该分支。
$envcc = "$ortRoot\onnxruntime\core\platform\posix\env.cc"
$etxt = Get-Content $envcc -Raw
if ($etxt -notmatch 'chaoxing-patch: musl') {
  $eold = '#if !defined(__APPLE__) && !defined(__ANDROID__) && !defined(__wasm__) && !defined(_AIX)'
  $enew = '#if !defined(__APPLE__) && !defined(__ANDROID__) && !defined(__wasm__) && !defined(_AIX) && !defined(__MUSL__) // [chaoxing-patch: musl has no pthread_setaffinity_np]'
  if (-not $etxt.Contains($eold)) { throw "patch anchor not found in $envcc" }
  Set-Content -Path $envcc -Value $etxt.Replace($eold, $enew) -NoNewline -Encoding UTF8
  Write-Host "patched $envcc (musl affinity)"
}

# Patch: DISABLE_CONTRIB_OPS 会排除 contrib 源码列表，但 CPU 提供者的
# fp16/conv.cc（由 MLAS_F16VEC_INTRINSICS_SUPPORTED 带入编译）仍引用 contrib
# 的辅助函数 GetFusedActivationAttr，导致链接失败。该辅助文件不含任何内核
# 注册，保留它无副作用。
$pc = "$ortRoot\cmake\onnxruntime_providers.cmake"
# 多行锚点匹配需要统一行尾（工作区检出的文件是 CRLF）
$ptxt = (Get-Content $pc -Raw).Replace("`r`n", "`n")
if ($ptxt -notmatch 'chaoxing-patch: fused_activation') {
  $pold = @'
if (onnxruntime_REDUCED_OPS_BUILD)
  substitute_op_reduction_srcs(onnxruntime_providers_src)
endif()
'@
  $pnew = @'
# [chaoxing-patch: fused_activation] keep helper needed by cpu/fp16/fp16_conv.cc
if (onnxruntime_DISABLE_CONTRIB_OPS)
  list(APPEND onnxruntime_providers_src "${ONNXRUNTIME_ROOT}/contrib_ops/cpu/fused_activation.cc")
endif()
if (onnxruntime_REDUCED_OPS_BUILD)
  substitute_op_reduction_srcs(onnxruntime_providers_src)
endif()
'@
  $count = ([regex]::Matches($ptxt, [regex]::Escape($pold))).Count
  if ($count -ne 1) { throw "patch anchor count in $pc is $count (expected 1)" }
  Set-Content -Path $pc -Value $ptxt.Replace($pold, $pnew) -NoNewline -Encoding UTF8
  Write-Host "patched $pc (fused_activation helper)"
}

# Patch: cpuid_info.cc 的 cpuinfo_* 调用块只有运行时布尔保护，没有编译期
# 保护；ENABLE_CPUINFO=OFF 时 cpuinfo 头文件不在包含路径里必然编译失败。
# 用 CPUINFO_SUPPORTED 宏包住，未启用时走 getauxval(AT_HWCAP) 回退。
$ci = "$ortRoot\onnxruntime\core\common\cpuid_info.cc"
$citxt = (Get-Content $ci -Raw).Replace("`r`n", "`n")
if ($citxt -notmatch 'chaoxing-patch: cpuinfo optional') {
  $copen = @'
  if (pytorch_cpuinfo_init_) {
    is_hybrid_ = cpuinfo_get_uarchs_count() > 1;
'@
  $copenNew = @'
#ifdef CPUINFO_SUPPORTED  // [chaoxing-patch: cpuinfo optional]
  if (pytorch_cpuinfo_init_) {
    is_hybrid_ = cpuinfo_get_uarchs_count() > 1;
'@
  $cclose = @'
  } else {
    has_arm_neon_dot_ = ((getauxval(AT_HWCAP) & HWCAP_ASIMDDP) != 0);
'@
  $ccloseNew = @'
  } else
#endif  // [chaoxing-patch: cpuinfo optional]
  {
    has_arm_neon_dot_ = ((getauxval(AT_HWCAP) & HWCAP_ASIMDDP) != 0);
'@
  if (([regex]::Matches($citxt, [regex]::Escape($copen))).Count -ne 1 -or
      ([regex]::Matches($citxt, [regex]::Escape($cclose))).Count -ne 1) {
    throw "patch anchor not unique in $ci"
  }
  $citxt = $citxt.Replace($copen, $copenNew).Replace($cclose, $ccloseNew)
  Set-Content -Path $ci -Value $citxt -NoNewline -Encoding UTF8
  Write-Host "patched $ci (cpuinfo optional)"
}

if ($Phase -in 'update', 'all') {
  Write-Host "=== [1/3] cmake configure + kernel reduction (build.py --update) ==="
  py -3 tools/ci_build/build.py @common --update
  if ($LASTEXITCODE -ne 0) { throw "build.py --update failed: $LASTEXITCODE" }
}

if ($Phase -in 'reduce', 'all') {
  Write-Host "=== [2/3] re-run kernel reduction with exact op whitelist ==="
  # build.py --update 内部调 reduce_ops 时，因未传 --minimal_build 会把
  # extended-minimal 需要的补充算子也加入白名单（多余）。这里用独立脚本按
  # 精确白名单重新生成 op_reduction.generated，再编译。
  py -3 tools/ci_build/reduce_op_kernels.py $opsCfg --cmake_build_dir "$buildDir\MinSizeRel"
  if ($LASTEXITCODE -ne 0) { throw "reduce_op_kernels.py failed: $LASTEXITCODE" }
}

if ($Phase -in 'build', 'all') {
  Write-Host "=== [3/3] ninja build (MinSizeRel) ==="
  py -3 tools/ci_build/build.py @common --build
  if ($LASTEXITCODE -ne 0) { throw "build.py --build failed: $LASTEXITCODE" }
  Get-Item "$buildDir\MinSizeRel\libonnxruntime.so" | Select-Object FullName, Length
}
