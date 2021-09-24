server.wait_for_open_port(80)

driver.get("http://server")
assert driver.find_element_by_css_selector("p").text == 'test'
