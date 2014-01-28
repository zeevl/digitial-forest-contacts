#!/usr/bin/env coffee
csv = require 'csv'
request = require 'request'

username = process.argv[1]
pwd = process.argv[2]

username = 'ross'
pwd = 'Lakers1!'
# username = 'steve'
# pwd = 'Lakers#1'

contacts = []

request = request.defaults
	jar: true
	followAllRedirects: true
	headers:
		'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/32.0.1700.77 Safari/537.36'
		'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
		'Accept-Encoding': 'gzip,deflate,sdch'

console.log 'Getting login page..'
request 'http://1891092.svc.e1m.net/email/scripts/loginuser.pl', (error, response, body) ->
	m = /loginuser\.pl\?EV1=(\d+)/.exec body
	if not m 
		console.log "ERROR! Couldn't find EV1 param!"
		process.exit

	login m[1]

login = (ev1) ->
	console.log "logging in (ev1: #{ev1})"
	request 
		url: "http://1891092.svc.e1m.net/email/scripts/loginuser.pl?EV1=#{ev1}"
		method: 'POST'
		form: 
			loginName: username
			user_pwd: pwd
			login: 'Login'
		(error, response, body) ->
			if response.statusCode is not 200
				console.log "ERROR! #{response.statusCode}"
				process.exit

			getWmPage()



getWmPage = ->
	console.log 'getting wm page...'
	request 'http://1891092.svc.e1m.net/eonapps/ft/wm/page/wm', (error, response, body) ->
		m = /"owner":(\d+)/g.exec body
		if not m 
			console.log "ERROR!  Couldn't find owner"
			console.log body
			process.exit

		getContactList parseInt(m[1]), 0

cids = []
getContactList = (owner, startIndex) ->
	console.log "getting contact list #{startIndex} - #{startIndex + 100}..."

	params = [
	  method: "p_none_Cards_retrieveCards"
	  params: [
	    shelf:
	      owner: owner
	      eonType: "PersonalShelfHandle"

	    path:
	      path: "/Personal"
	      eonType: "Path"

	    eonType: "AddressBookHandle"
	  , startIndex, startIndex + 100, [
	    attribute: "lastName"
	    ascending: true
	    eonType: "SortCriteria"
	  ], null, "America/Los_Angeles"]
	  id: 0
	]

	request
		url: "http://1891092.svc.e1m.net/eonapps/ft/wm/raw?rand=#{Math.random()}"
		method: 'POST'
		headers: 
			Accept: '*/*'
			'Content-Type': 'text/xml;charset=UTF-8'
		body: JSON.stringify params
		(error, response, body) ->
			results = JSON.parse body
			cids.push c.docID for c in results[0].result.results
			
			if cids.length == results[0].result.length
				getContact owner, id for id in cids
			else
				newStart = Math.min(startIndex + 100, results[0].result.length) 
				getContactList owner, newStart

pendingContacts = 0 

getContact = (owner, id) ->
	params = [
	  method: "p_none_Cards_retrieveCard"
	  params: [
	    shelf:
	      owner: owner
	      eonType: "PersonalShelfHandle"

	    path:
	      path: "/Personal"
	      eonType: "Path"

	    eonType: "AddressBookHandle"
	  , id]
	  id: 0
	]

	pendingContacts++

	request
		url: "http://1891092.svc.e1m.net/eonapps/ft/wm/raw?rand=#{Math.random()}"
		method: 'POST'
		headers: 
			Accept: '*/*'
			'Content-Type': 'text/xml;charset=UTF-8'
		body: JSON.stringify params
		(error, response, body) ->
			results = JSON.parse body
			result = results[0].result

			try
				contact =  
					'First Name': result.name.givenName
					'Middle Name': result.name.additionalNames[0]?.middle
					'Last Name': result.name.familyName
					'Title': result.titles[0]?.value
					'Mobile Phone': ''
					'Business Fax': ''
					'Business Phone': ''
					'Home Phone': ''
					'Other Phone': ''
					'E-mail Address': ''
					'E-mail 2 Address': ''
					'E-mail 3 Address': ''

				for phone in result.telephoneNumbers
					# console.log JSON.stringify phone
					switch phone.types[0]
						when 'MOBILE' then contact['Mobile Phone'] = phone.value
						when 'WORK' 
							if phone.types[1] is 'FAX'
								contact['Business Fax'] = phone.value
							else
								contact['Business Phone'] = phone.value 
						when 'FAX' then throw 'FAX NUMBER FOUND!'
						when 'HOME' then contact['Home Phone'] = phone.value
						when 'OTHER' then contact['Other Phone'] = phone.value
						else throw "Unknown number!! #{phone.types[0]}"

				for addy in result.deliveryAddresses
					throw 'ADDRESS FOUND!!!'

				# throw 'NOTES FOUND' unless result.notes.length is 0 

				for email in result.emailAddresses
					switch email.types[0]
						when 'HOME', 'INTERNET' then contact['E-mail Address'] = email.value
						when 'WORK' then contact['E-mail 2 Address'] = email.value
						when 'OTHER' then contact['E-mail 3 Address'] = email.value

			catch ex
				console.log "An EXCEPTION HAPPENED"
				console.log result
				throw ex

			contacts.push contact


			pendingContacts--
			console.log pendingContacts
			writeCsv() unless pendingContacts > 0

writeCsv = ->
	console.log "Writing CSV.."
	columns = (k for k of contacts[0])
	buf = (csv().from contacts, columns: columns).to "./#{username}.csv", 
		header: true
		columns: columns

