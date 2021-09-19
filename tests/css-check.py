driver.get("http://webserver")
body = driver.find_element_by_tag_name("body")
assert body.value_of_css_property("display") == "flex"
open("done", "w")
