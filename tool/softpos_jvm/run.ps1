param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$payRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (!$OutputDirectory) { $OutputDirectory=Join-Path $env:TEMP ('pay002-jvm-'+[guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$payCache=Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1'
function Jar([string]$artifact,[string]$pattern) { (Get-ChildItem -LiteralPath (Join-Path $payCache $artifact) -Recurse -Filter $pattern | Select-Object -First 1).FullName }
$payCompiler=Jar 'org.jetbrains.kotlin\kotlin-compiler-embeddable' 'kotlin-compiler-embeddable-1.9.0.jar'
$payStdlib=Jar 'org.jetbrains.kotlin\kotlin-stdlib' 'kotlin-stdlib-1.9.24.jar'
$payReflect=Jar 'org.jetbrains.kotlin\kotlin-reflect' 'kotlin-reflect-1.6.10.jar'
$payTrove=Jar 'org.jetbrains.intellij.deps\trove4j' '*.jar'
$payAnnotations=Jar 'org.jetbrains\annotations' '*.jar'
$payJson=Jar 'org.json\json' '*.jar'
$payJava='C:\Program Files\Microsoft\jdk-21.0.8.9-hotspot\bin\java.exe'
$payCompilerCp=@($payCompiler,$payStdlib,$payReflect,$payTrove,$payAnnotations) -join ';'
$payRuntimeCp=@($payStdlib,$payJson,$payAnnotations) -join ';'
$paySources=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.kt' | ForEach-Object FullName)
$paySources+=Join-Path $payRoot 'android\app\src\main\kotlin\net\mithqal\softpos\SoftPosBridgeCore.kt'
& $payJava -cp $payCompilerCp org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -classpath $payRuntimeCp -d "$OutputDirectory\contract.jar" @paySources 2>&1 | Tee-Object "$OutputDirectory\compile.log"
$payCode=$LASTEXITCODE
"EXIT=$payCode" | Add-Content "$OutputDirectory\compile.log"
if ($payCode -ne 0) {exit $payCode}
& $payJava -cp "$OutputDirectory\contract.jar;$payRuntimeCp" CoreContractKt 2>&1 | Tee-Object "$OutputDirectory\test.log"
$payCode=$LASTEXITCODE
"EXIT=$payCode" | Add-Content "$OutputDirectory\test.log"
exit $payCode
