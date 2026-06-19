Import-Module ActiveDirectory

function Show-Menu {
    Clear-Host
    Write-Host " 1. look up user info (AD properties)"
    Write-Host " 2. reset password (with force change)"
    Write-Host " 3. unlock locked account"
    Write-Host " 4. list all locked accounts"
    Write-Host " 5. add/remove user from group"
    Write-Host " 6. get computer system info"
    Write-Host " 7. check service status on remote machine"
    Write-Host " 8. generate disk space report"
    Write-Host " 9. bulk create users from CSV"
    Write-Host "10. export group membership to CSV"
    Write-Host " X. exit"
}

while ($true) {
    Show-Menu
    $Selection = Read-Host "select an option"
    Write-Host ""

    switch ($Selection) {
        '1' {
            $User = Read-Host "Enter username (SamAccountName)"
            try {
                $UserInfo = Get-ADUser -Identity $User -Properties * -ErrorAction Stop
                $UserInfo | Select-Object Name, SamAccountName, EmailAddress, Title, Department, Enabled, LockedOut, PasswordExpired, LastLogonDate | Format-List
                Write-Host "[+] User info retrieved successfully" -ForegroundColor Green
            } catch {
                Write-Host "[X] User '$User' not found. Reason: $_" -ForegroundColor Red
            }
        }
        '2' {
            $User = Read-Host "Enter username"
            $Password = Read-Host "Enter new password" -AsSecureString
            try {
                Set-ADAccountPassword -Identity $User -NewPassword $Password -Reset -Force -ErrorAction Stop
                Set-ADUser -Identity $User -ChangePasswordAtLogon $true -ErrorAction Stop
                Write-Host "[+] Password reset and force change at next login for '$User'." -ForegroundColor Green
            } catch {
                Write-Host "[X] Failed to reset password for '$User'. Reason: $_" -ForegroundColor Red
            }
        }
        '3' {
            $User = Read-Host "Enter username"
            try {
                Unlock-ADAccount -Identity $User -ErrorAction Stop
                Write-Host "[+] Account '$User' unlocked." -ForegroundColor Green
            } catch {
                Write-Host "[X] Failed to unlock account '$User'. Reason: $_" -ForegroundColor Red
            }
        }
        '4' {
            # 4. List all locked accounts
            $LockedUsers = Search-ADAccount -LockedOut -UsersOnly
            if ($null -eq $LockedUsers -or $LockedUsers.Count -eq 0) {
                Write-Host "No locked-out accounts found." -ForegroundColor Green
            } else {
                Write-Host "[!] Found $($LockedUsers.Count) locked accounts:" -ForegroundColor Yellow
                $LockedUsers | Select-Object Name, SamAccountName | Format-Table -AutoSize
            }
        }
        '5' {
            $User = Read-Host "Enter username"
            $Group = Read-Host "Enter group name"
            $Action = Read-Host "Enter action (Add/Remove)"
            try {
                if ($Action -match "^a") {
                    Add-ADGroupMember -Identity $Group -Members $User -ErrorAction Stop
                    Write-Host "[+] Added '$User' to '$Group'." -ForegroundColor Green
                } elseif ($Action -match "^r") {
                    Remove-ADGroupMember -Identity $Group -Members $User -Confirm:$false -ErrorAction Stop
                    Write-Host "[+] Removed '$User' from '$Group'." -ForegroundColor Green
                } else {
                    Write-Host "[X] Invalid. Please enter Add or Remove." -ForegroundColor Red
                }
            } catch {
                Write-Host "[X] Failed to update group membership. Reason: $_" -ForegroundColor Red
            }
        }
        '6' {
            $Computer = Read-Host "Enter computer name (leave blank for localhost)"
            if ([string]::IsNullOrWhiteSpace($Computer)) { $Computer = $env:COMPUTERNAME }
            try {
                $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Computer -ErrorAction Stop
                $CS = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $Computer -ErrorAction Stop
                
                # FIXED: Added $() around $Computer to prevent scope parser error
                Write-Host "[+] System Info for $($Computer):" -ForegroundColor Green
                [PSCustomObject]@{
                    Manufacturer = $CS.Manufacturer
                    Model = $CS.Model
                    OSVersion = $OS.Caption
                    RAM_GB = [math]::Round($CS.TotalPhysicalMemory / 1GB, 2)
                } | Format-List
            } catch {
                Write-Host "[X] Failed to get system info for '$Computer'. Reason: $_" -ForegroundColor Red
            }
        }
        '7' {
            $Computer = Read-Host "Enter remote computer name"
            $Service = Read-Host "Enter service name (e.g., Spooler) or leave blank for all"
            try {
                if ([string]::IsNullOrWhiteSpace($Service)) {
                    Get-Service -ComputerName $Computer -ErrorAction Stop | Out-GridView
                    Write-Host "[+] Services opened in GridView." -ForegroundColor Green
                } else {
                    $Svc = Get-Service -ComputerName $Computer -Name $Service -ErrorAction Stop
                    Write-Host "[+] Service '$Service' status on '$Computer': $($Svc.Status)" -ForegroundColor Green
                }
            } catch {
                Write-Host "[X] Failed to check services on '$Computer'. Reason: $_" -ForegroundColor Red
            }
        }
        '8' {
            $Computer = Read-Host "Enter computer name (leave blank for localhost)"
            if ([string]::IsNullOrWhiteSpace($Computer)) { $Computer = $env:COMPUTERNAME }
            try {
                $DiskInfo = Get-Volume -CimSession $Computer -ErrorAction Stop | 
                    Where-Object { $_.DriveLetter -ne $null } | 
                    Select-Object DriveLetter, 
                        @{Name="FreeSpace(GB)";Expression={[math]::Round($_.SizeRemaining / 1GB, 2)}},
                        @{Name="TotalSize(GB)";Expression={[math]::Round($_.Size / 1GB, 2)}},
                        @{Name="PercentFree";Expression={[math]::Round(($_.SizeRemaining / $_.Size) * 100, 1)}}
                
                # FIXED: Added $() around $Computer to prevent scope parser error
                Write-Host "[+] Disk Space for $($Computer):" -ForegroundColor Green
                $DiskInfo | Format-Table -AutoSize
            } catch {
                Write-Host "[X] Failed to get disk space report for '$Computer'. Reason: $_" -ForegroundColor Red
            }
        }
        '9' {
            $CsvPath = Read-Host "Enter path to CSV file (example: C:\IT-Scripts\employees.csv)"            
            if (-not (Test-Path -Path $CsvPath)) {
                Write-Host "[X] CSV file not found at $CsvPath." -ForegroundColor Red
            } else {
                $Users = Import-Csv -Path $CsvPath                
                foreach ($User in $Users) {
                    $SamAccountName = "$($User.FirstName).$($User.LastName)".ToLower()
                    $UPN = "$SamAccountName@helpdesk.lab"
                    
                    $ExistingUser = Get-ADUser -Filter {SamAccountName -eq $SamAccountName}
                    if ($ExistingUser) {
                        Write-Host "[-] User '$SamAccountName' already exists. Skipping..." -ForegroundColor Yellow
                        continue
                    }
                    
                    $TempPassword = "Temp2026!$($User.FirstName)"
                    $SecurePassword = ConvertTo-SecureString $TempPassword -AsPlainText -Force
                    
                    try {
                        # Create AD User
                        New-ADUser -Name "$($User.FirstName) $($User.LastName)" `
                                   -GivenName $User.FirstName `
                                   -Surname $User.LastName `
                                   -SamAccountName $SamAccountName `
                                   -UserPrincipalName $UPN `
                                   -AccountPassword $SecurePassword `
                                   -ChangePasswordAtLogon $true `
                                   -Enabled $true `
                                   -ErrorAction Stop
                        Write-Host "[+] Created: $SamAccountName" -ForegroundColor Green
                    } catch {
                        Write-Host "[X] Failed to create: $SamAccountName. Reason: $_" -ForegroundColor Red
                    }
                }
            }
        }
        '10' {
            $Group = Read-Host "Enter group name"
            $ExportPath = Read-Host "Enter export path (example: C:\Reports\GroupMembers.csv)"            
            $ExportDir = Split-Path $ExportPath
            if (-not (Test-Path -Path $ExportDir)) {
                New-Item -ItemType Directory -Path $ExportDir | Out-Null
            }

            try {
                $Members = Get-ADGroupMember -Identity $Group -ErrorAction Stop | Select-Object Name, SamAccountName, objectClass
                if ($Members) {
                    $Members | Export-Csv -Path $ExportPath -NoTypeInformation -Force
                    Write-Host "[+] Group membership exported to: $ExportPath" -ForegroundColor Green
                } else {
                    Write-Host "[-] No members found in group '$Group'." -ForegroundColor Yellow
                }
            } catch {
                Write-Host "[X] Failed to export group membership for '$Group'. Reason: $_" -ForegroundColor Red
            }
        }
        # FIXED: PowerShell switch is case-insensitive by default. 'X' covers both.
        'X' {
            Write-Host "Exiting ..." -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "[X] Invalid. try again" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Press any key to return to the menu..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}