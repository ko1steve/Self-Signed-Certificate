function GetIniData($iniPath){
    $iniData = @{}
    $section = ""

    foreach ($line in Get-Content $iniPath) {
        $line = $line.Trim()

        if ($line -match "^\s*\[.*\]\s*$") {
            # 取得區段名稱
            $section = $line -replace "^\[|\]$"
            $iniData[$section] = @{}
        } elseif ($line -match "^\s*[^;#].*=") {
            # 取得鍵值對
            $parts = $line -split "=", 2
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            if ($section -ne "") {
                $iniData[$section][$key] = $value
            }
        }
    }
    return $iniData
}
# =============================================

# ===== 顯示資訊 =====

Write-Host "===== 顯示資訊 ====="

$iniPath = "settings.ini"
$iniData = GetIniData($iniPath)

$openssl = $iniData['OpenSSL']['exe_path']
$openssl_config = $iniData['OpenSSL']['config_path']

$keytool = $iniData['Keytool']['exe_path']

Write-Host "openssl=[$($openssl)]"
Write-Host "openssl_config=[$($openssl_config)]"

# ===== Step 1. 產生根憑證私鑰 =====

Write-Host "===== Step 1. 產生根憑證私鑰 ====="

$root_key_output = $iniData['Root Certificate Private Key']['output']
$root_key_length = $iniData['Root Certificate Private Key']['length']

Write-Host "command=[& $openssl genrsa -out $root_key_output $root_key_length]"
& $openssl genrsa -out $root_key_output $root_key_length

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 2. 產生自簽根憑證 =====

Write-Host "===== Step 2. 產生自簽根憑證 ====="

$root_pem_output =  $iniData['Self-Signed Root PEM Certificate']['output']
$root_pem_validDays = $iniData['Self-Signed Root PEM Certificate']['validDays']
$root_pem_subject = $iniData['Self-Signed Root PEM Certificate']['subject']

Write-Host "command=[& $openssl req -x509 -new -nodes -key $root_key_output -sha256 -days $root_pem_validDays -out $root_pem_output -subj $root_pem_subject -config $openssl_config]"
& $openssl req -x509 -new -nodes -key $root_key_output -sha256 -days $root_pem_validDays -out $root_pem_output -subj $root_pem_subject -config $openssl_config

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 3. 將根憑證由 PEM 格式轉為 DER 格式 =====

Write-Host "===== Step 3. 將根憑證由 PEM 格式轉為 DER 格式  ====="

$root_cer_output =  $iniData['Self-Signed Root CER Certificate']['output']

Write-Host "command=[& $openssl x509 -in $root_pem_output -outform DER -out $root_cer_output]"
& $openssl x509 -in $root_pem_output -outform DER -out $root_cer_output

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 4. 產生伺服器憑證私鑰 =====

Write-Host "===== Step 4. 產生伺服器憑證私鑰 ====="

$server_key_output = $iniData['Server Certificate Private Key']['output']
$server_key_length = $iniData['Server Certificate Private Key']['length']

Write-Host "command=[& $openssl genrsa -out $server_key_output $server_key_length]"
& $openssl genrsa -out $server_key_output $server_key_length

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 5. 產生伺服器憑證簽署請求檔 (CSR) =====

Write-Host "===== Step 5. 產生伺服器憑證簽署請求檔 (CSR) ====="

$server_csr_output = $iniData['Server Certificate Sign Request']['output']
$server_csr_san_path = $iniData['Server Certificate Sign Request']['san_cnf_path']

Write-Host "command=[& $openssl req -new -key $server_key_output -out $server_csr_output -config $server_csr_san_path]"
& $openssl req -new -key $server_key_output -out $server_csr_output -config $server_csr_san_path

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 6. 產生伺服器憑證 (PEM) =====

Write-Host "===== Step 6. 產生伺服器憑證 (PEM) ====="

$server_pem_output = $iniData['Server PEM Certificate']['output']
$server_pem_validDays = $iniData['Server PEM Certificate']['validDays']

Write-Host "command=[& $openssl x509 -req -in $server_csr_output -CA $root_cer_output -CAkey $root_key_output -CAcreateserial -out $server_pem_output -days $server_pem_validDays -sha256 -extfile $server_csr_san_path -extensions req_ext 2>$null]"
& $openssl x509 -req -in $server_csr_output -CA $root_cer_output -CAkey $root_key_output -CAcreateserial -out $server_pem_output -days $server_pem_validDays -sha256 -extfile $server_csr_san_path -extensions req_ext 2>$null

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

$server_pem_full_output = $iniData['Server PEM Full Certificate']['output']
Get-Content $server_pem_output.Trim('"'), $root_pem_output.Trim('"') | Set-Content $server_pem_full_output.Trim('"')

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

$server_pem_output = $server_pem_full_output

Write-Host "執行成功"
Write-Host ""



# ===== Step 7. 將伺服器憑證由 PEM 格式轉為 DER 格式  =====

Write-Host "===== Step 7. 將伺服器憑證由 PEM 格式轉為 DER 格式 ====="

$server_cer_output = $iniData['Server DER Certificate']['output']

Write-Host "command=[& $openssl x509 -in $server_pem_output -inform DER -out $server_cer_output]"
& $openssl x509 -in $server_pem_output -inform PEM -out $server_cer_output

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 8. 將伺服器憑證由 DER 格式轉為 PFX 格式 =====

Write-Host "===== Step 8. 將伺服器憑證由 DER 格式轉為 PFX 格式 ====="

$server_pfx_output = $iniData['Server PFX Certificate']['output']
$server_pfx_password = $iniData['Server PFX Certificate']['password']

Write-Host "command=[& $openssl pkcs12 -export -out $server_pfx_output -inkey $server_key_output -in $server_pem_output -certfile $root_pem_output -passout pass:$server_pfx_password]"
& $openssl pkcs12 -export -out $server_pfx_output -inkey $server_key_output -in $server_pem_output -certfile $root_pem_output -passout pass:$server_pfx_password

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""



# ===== Step 9. 將伺服器憑證由 PFX 格式轉為 JKS 格式 ======

Write-Host "===== Step 9. 將伺服器憑證由 PFX 格式轉為 JKS 格式 ====="

$server_jks_output = $iniData['Server JKS Certificate']['output'].Trim('"')

Write-Host "清除 JKS 路徑 [$server_jks_output] ..."
if (Test-Path $server_jks_output) { Remove-Item $server_jks_output -Force }
Write-Host "確認清除"

Write-Host "command=[& $keytool -importkeystore -srckeystore $server_pfx_output -srcstoretype PKCS12 -srcstorepass $server_pfx_password -destkeystore $server_jks_output -deststoretype JKS -deststorepass $server_pfx_password 2>$null]"
& $keytool -importkeystore -srckeystore $server_pfx_output -srcstoretype PKCS12 -srcstorepass $server_pfx_password -destkeystore $server_jks_output -deststoretype JKS -deststorepass $server_pfx_password 2>$null

if ($LASTEXITCODE -ne 0) {
  Write-Host "執行失敗"
  exit 1
}

Write-Host "執行成功"
Write-Host ""