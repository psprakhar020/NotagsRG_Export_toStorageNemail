#Parameters Definition

#Paramters for outputfile
$date= Get-date -UFormat "%d%m%Y"
$outputfile = "RGwithoutTags_"+$date+".csv"
$arr= @()


#Pass the credentials
#Need to define credential by name TEST in credential tab of automation account
$User = "xxxx" #Define emailID of the user from which mails need to be sent
$credentials = Get-AutomationPSCredential -Name 'TEST' #credential of the account from where email needs to be sent
$to = "xxxx" #Define emailID of the user to which mail needs to be sent
$smtp = "smtp.office365.com" #SMTP server
$port= #Port of the smtp server
$body = "Attached List of resource group that does not have tags"


#Parmeters for Storage Account
$AzStorAccName = "xxxxx"
$AzResGroup = "xxxxx-rg"
$filesharename = "xxxx"
$localFile = ".\"+$outputfile 
$dest = "RG_without_Tags\"+$outputfile


#Connect to Tenant Domain id
Try
{ 
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
    Connect-AzureAD -TenantID $Conn.TenantID -ApplicationId $Conn.ApplicationId -CertificateThumbprint $Conn.CertificateThumbprint
}
Catch
{
    $ErrorMessage = $_.Exception.Message
    Write-Error $ErrorMessage
} 


 $allResourceGroups = Get-AzResourceGroup
    ForEach ($group in $allResourceGroups) 
    {
        $gp = $group.ResourceGroupName
        Write-Output "Processing $($gp) ($($sub.Name))"

        if ($group.Tags.Count -ne 0) 
        {
            
            $resources = Get-AzResource -ResourceGroupName $gp
            foreach ($r in $resources)
            {
                $tagChanges = $false
                $resourcetags = (Get-AzResource -ResourceId $r.ResourceId).Tags
                
                if ($resourcetags)
                {
                
                    foreach ($key in $group.Tags.Keys)
                    {
                        if (-not($resourcetags.ContainsKey($key)))
                        {
                            Write-Output "ADD: $($r.Name) - $key"
                            $resourcetags.Add($key, $group.Tags[$key])
                            $tagChanges = $True
                        }
                        else
                        {
                            if ($resourcetags[$key] -eq $group.Tags[$key])
                            {
                                # Key is up-to-date
                            }
                            else
                            {
                                Write-Output "UPD: $($r.Name) - $key"
                                $null = $resourcetags.Remove($key)
                                $resourcetags.Add($key, $group.Tags[$key])
                                $tagChanges = $True
                            }
                        }
                    }
                    $tagsToWrite = $resourcetags 
                }
                else
                {
                    # All tags missing
                    Write-Output "ADD: $($r.Name) - All tags from RG"
                    $tagsToWrite = $group.Tags
                    $tagChanges = $True
                }

                if ($tagChanges)
                {
                    try
                    {
                        $rUPD = Set-AzResource -Tag $tagsToWrite -ResourceId $r.ResourceId -Force -ErrorAction Stop
                    }
                    catch
                    {
                        # Write-Error "$($r.Name) - $($group.ResourceID) : $_.Exception"
                    }
                }
            }
        }
        else
        {
            
            $object1 = [PSCustomobject]@{                
                ResourceGroupName= $resourceGroupName				
		    }
 
            $arr += $object1
        
            Write-Output "$resourceGroupName has no tags set."
        }


    }

$arr | Export-Csv -Path $outputfile -NoTypeInformation -Force

# get the central storage account name
$AzStrAct = Get-AzureRmStorageAccount -Name $AzStorAccName -ResourceGroupName $AzResGroup

#get the storage account key
$AzStrKey = Get-AzureRmStorageAccountKey -Name $AzStorAccName -ResourceGroupName $AzResGroup

#set the storage account context
$AzStrCtx = New-AzureStorageContext $AzStorAccName -StorageAccountKey $AzStrKey[0].Value

#transfer the file to common storage
Set-AzureStorageFileContent -ShareName $filesharename -Context $AzStrCtx –Source $localFile -Path $dest 

#Send mail to respective user
Send-MailMessage -From $User -To $to -Subject "Azure Virtual Machine Orphan Disks" -Body $body -Attachments $outputfile -Priority High -Port $port -SmtpServer $smtp -Credential $credentials -UseSsl

#Delete the file once file has been transfered
rm $outputfile
