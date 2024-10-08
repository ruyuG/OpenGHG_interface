#!/bin/bash


SERVER="bp1-login.acrc.bris.ac.uk"
USERNAME=""
GITHUB_REPO_URL="https://github.com/ruyuG/OpenGHG_interface.git"  # Github URL

# username
read -p "Enter your username for $SERVER: " USERNAME

# SSH login test
echo "Testing SSH login..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 $USERNAME@$SERVER exit 2>/dev/null; then
    echo "SSH login successful. Proceeding with the setup..."
else
    echo "SSH login failed. Setting up SSH key for password-less login..."
    # check ssh key
    SSH_KEY="$HOME/.ssh/id_rsa"
    if [ ! -f "$SSH_KEY" ]; then
        echo "No SSH key found. Generating one..."
        ssh-keygen -t rsa -N "" -f $SSH_KEY
        echo "SSH key generated."
    else
        echo "SSH key already exists."
    fi

    # try to copy SSH key to server
    echo "Trying to copy SSH key to $SERVER..."
    ssh-copy-id -i $SSH_KEY.pub $USERNAME@$SERVER
fi


# login server and set env
ssh -tt $USERNAME@$SERVER bash << EOF
    set -e

    echo "Loading Python module..."
    module load lang/python/miniconda/3.10.10.cuda-12 || { echo "Failed to load Python module"; exit 1; }

    # Check Virtual environment 'streamlit-env
    if [ -d "\$HOME/streamlit-env" ]; then
        echo "Virtual environment 'streamlit-env' already exists. Activating it..."
        source \$HOME/streamlit-env/bin/activate || { echo "Failed to activate environment"; exit 1; }
    else
        echo "Creating Python virtual environment..."
        python -m venv \$HOME/streamlit-env || { echo "Failed to create environment"; exit 1; }
        source \$HOME/streamlit-env/bin/activate || { echo "Failed to activate environment"; exit 1; }
    fi

    echo "Upgrading pip..."
    pip install --upgrade pip || { echo "Failed to upgrade pip"; exit 1; }

    # Clone or update GitHub repository
    REPO_NAME="openghg_interface"

    if [ ! -d "\$REPO_NAME" ]; then
        echo "Cloning the GitHub repository..."
        git clone $GITHUB_REPO_URL \$REPO_NAME || { echo "Failed to clone repository"; exit 1; }
    else
        echo "Repository already exists. Updating..."
        cd \$REPO_NAME
        git pull || { echo "Failed to update repository"; exit 1; }
        cd ..
    fi

    echo "Installing dependencies from requirements.txt..."
    pip install -r \$REPO_NAME/requirements.txt || { echo "Failed to install dependencies"; exit 1; }

    echo "Configuring openghg..."
    expect -c '
        set timeout 30
        spawn python
        expect ">>>"
        send "from openghg.util import create_config\r"
        send "create_config(silent=False)\r"
        expect "Would you like to update the path? (y/n):"
        send "n\r"
        set store_names [list "obs_store1" "spital_store2"]
        set store_paths [list "/group/chemistry/acrg/object_stores/paris/obs_nir_2024_01_25_store_zarr" "/group/chemistry/acrg/object_stores/updated/shared_store_zarr"]
        set store_permissions [list "r" "r"] 
        set store_count [llength \$store_names]
        for {set i 0} {\$i < \$store_count} {incr i} {
            expect "Would you like to add another object store? (y/n):"
            send "y\r"
            expect "Enter the name of the store:"
            send "[lindex \$store_names \$i]\r"
            expect "Enter the object store path:"
            send "[lindex \$store_paths \$i]\r"
            expect "Enter object store permissions:"
            send "[lindex \$store_permissions \$i]\r"
        }
        expect "Would you like to add another object store? (y/n):"
        send "n\r"
        expect "Configuration written"
        send "exit()\r"
        expect eof
    '
    
    echo "Environment setup complete."
    
    # Start an interactive shell to keep the connection open
    echo "Entering interactive mode..."
    exec bash
EOF

echo "Installation and configuration completed successfully."

