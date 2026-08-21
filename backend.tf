terraform {
  required_version = "~> 1.15.0"

  cloud {
    
    organization = "DigitalTech"

    workspaces {
      name = "asg-incid"
    }
  }
}

#