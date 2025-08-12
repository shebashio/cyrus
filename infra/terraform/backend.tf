terraform { 
  cloud { 
    
    organization = "shebash" 

    workspaces { 
      name = "cyrus" 
    } 
  } 
}