# =================================================================================
# 5. アウトプット（接続用IPアドレスの表示）
# =================================================================================
output "ec2_public_ip" {
  value       = aws_instance.app_server.public_ip
  description = "起動したEC2のパブリックIPアドレスです"
}

output "ec2_private_ip" {
  value       = aws_instance.app_server.private_ip
  description = "EC2のプライベートIPアドレスです"
}
