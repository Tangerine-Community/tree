# halts the request and logs the error
def halt_error(code, message, log_message)
  $l.error log_message
  halt code, { :error => message }.to_json
end
