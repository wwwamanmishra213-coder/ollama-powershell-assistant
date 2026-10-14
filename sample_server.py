"""
Sample application file for testing CodeAssistant.ps1
"""
import os
import json

def process_user_data(user_input):
    # Intentional basic implementation to test review & refactoring
    data = json.loads(user_input)
    username = data.get("username", "")
    role = data.get("role", "guest")
    
    # Missing input validation and error handling
    filepath = f"./records/{username}.json"
    
    with open(filepath, "w") as f:
        f.write(json.dumps(data))
        
    return {"status": "saved", "user": username}

if __name__ == "__main__":
    print("Sample server ready.")
