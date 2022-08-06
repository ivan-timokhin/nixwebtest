from selenium.webdriver.common.by import By

webserver.start()
webserver.wait_for_open_port(80)

driver.get("http://webserver")
body = driver.find_element(By.TAG_NAME, "body")
assert body.value_of_css_property("display") == "flex"
open("done", "w")
