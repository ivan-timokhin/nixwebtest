from selenium.webdriver.common.by import By

server.wait_for_open_port(80)

driver.get("http://server")
assert driver.find_element(By.CSS_SELECTOR, "p").text == 'test'
