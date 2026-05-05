import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

class MailUtil:
    # 이메일 설정
    smtp_server = ""
    smtp_port = 0
    username = ""
    password = ""

    @staticmethod
    def init_mail(smtp_server, smtp_port, username, password):
        MailUtil.smtp_server = smtp_server
        MailUtil.smtp_port = smtp_port
        MailUtil.username = username
        MailUtil.password = password

    @staticmethod
    def send_mail(sender, receiver, subject, body_text, localhost_mode = False):
        # 이메일 메시지 구성
        msg = MIMEMultipart()
        msg['From'] = sender
        msg['To'] = receiver
        msg['Subject'] = subject
        msg.attach(MIMEText(body_text, 'plain'))

        # SMTP 서버 연결 및 이메일 보내기
        try:
            server = smtplib.SMTP(MailUtil.smtp_server, MailUtil.smtp_port)
            #server.set_debuglevel(1)  # Enable debug output
            if localhost_mode:
                server.ehlo('localhost')
            server.starttls()
            if localhost_mode:
                server.ehlo('localhost')
            server.login(MailUtil.username, MailUtil.password)
            server.sendmail(sender, receiver, msg.as_string())
            server.quit()
            return None
        except Exception as e:
            return e

# Usage example
#MailUtil.init_mail('smtp.example.com', 587, 'username', 'password')
#MailUtil.send_mail('sender@example.com', 'receiver@example.com', 'Test Subject', 'Test Body')
