on extract_code(subject_text)
	set shell_cmd to "printf %s " & quoted form of subject_text & " | /usr/bin/grep -Eo '[0-9]{6}' | /usr/bin/head -n 1"
	try
		return do shell script shell_cmd
	on error
		return ""
	end try
end extract_code

on inbox_names()
	return {"INBOX", "Inbox", "收件箱"}
end inbox_names

on run argv
	tell application "Mail"
		check for new mail
		delay 5
		
		set wanted_mailboxes to my inbox_names()
		
		repeat with acct in every account
			try
				repeat with mb in (mailboxes of acct)
					try
						if (wanted_mailboxes contains (name of mb as text)) then
							set total_messages to count of messages of mb
							set upper_bound to total_messages
							if upper_bound > 25 then set upper_bound to 25
							
							repeat with i from 1 to upper_bound
								set m to message i of mb
								set sender_text to sender of m as text
								set subject_text to subject of m as text
								
								if sender_text contains "OpenAI" or sender_text contains "tm.openai.com" or subject_text contains "ChatGPT 代码" or subject_text contains "ChatGPT code" then
									set code_text to my extract_code(subject_text)
									if code_text is not "" then
										return code_text
									end if
								end if
							end repeat
						end if
					end try
				end repeat
			end try
		end repeat
	end tell
	
	error "No recent OpenAI / ChatGPT verification code found in the inbox view"
end run
