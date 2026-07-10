terraform {
  required_version = "1.15.8"

  cloud {
    
    organization = "DigitalTech"

    workspaces {
      name = "asg-incid"
    }
  }
}

#