desktop:
if desktop == "kde"
then ./kde
else if desktop == "qtile"
then ./qtile
else throw "desktop ${desktop} is not supported"
