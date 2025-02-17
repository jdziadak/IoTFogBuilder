import subprocess
import datetime

def get_git_info():
    # Get the latest commit hash
    commit_hash = subprocess.check_output(['git', 'rev-parse', 'HEAD']).strip().decode('utf-8')
    
    # Get the commit date
    commit_date = subprocess.check_output(['git', 'log', '-1', '--format=%cd']).strip().decode('utf-8')
    
    # Format commit date to "YYYY-MM-DD"
    commit_date = datetime.datetime.strptime(commit_date, "%a %b %d %H:%M:%S %Y %z").strftime('%Y-%m-%d')
    
    # Get the commit user
    commit_user = subprocess.check_output(['git', 'log', '-1', '--format=%an']).strip().decode('utf-8')
    
    return commit_hash, commit_date, commit_user

def generate_version():
    commit_hash, commit_date, commit_user = get_git_info()
    
    version = f"v1.0-commit-{commit_date}-{commit_hash}|{commit_user}"
    return "Current version: " + version