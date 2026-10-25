variable "rg_name" {
  type = string
}

variable "instance_number" {
  type    = number
  default = 1
}

variable "location" {
  type = string
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
