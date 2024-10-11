# Import the Active Directory module
Import-Module ActiveDirectory

# Define the base parameters
$domain = "nextlevel.local"
$usersPath = "CN=Users,DC=nextlevel,DC=local"
$passwordString = "P@ssw0rd123!"
$password = ConvertTo-SecureString $passwordString -AsPlainText -Force

# Function to create a user
function CreateUser($username, $firstname, $lastname) {
    $userPrincipalName = "$username@$domain"
    
    try {
        # Check if the user already exists
        if (Get-ADUser -Filter {SamAccountName -eq $username} -ErrorAction Stop) {
            Write-Host "User $username already exists. Skipping."
        } else {
            New-ADUser -SamAccountName $username `
                       -UserPrincipalName $userPrincipalName `
                       -Name "$firstname $lastname" `
                       -GivenName $firstname `
                       -Surname $lastname `
                       -Enabled $true `
                       -ChangePasswordAtLogon $false `
                       -Path $usersPath `
                       -AccountPassword $password `
                       -ErrorAction Stop

            Write-Host "User $username created successfully in the Users container."
        }
    } catch {
        Write-Host ("Error creating user {0}: {1}" -f $username, $_.Exception.Message)
    }
}

# Create dummy users
CreateUser "jsmith" "John" "Smith"
CreateUser "jdoe" "Jane" "Doe"
CreateUser "bbrown" "Bob" "Brown"
CreateUser "agreen" "Alice" "Green"
CreateUser "mwilson" "Mike" "Wilson"

Write-Host "Dummy user creation process completed."