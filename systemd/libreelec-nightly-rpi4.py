#!/usr/bin/env python

from bs4 import BeautifulSoup
import requests

def latest_img(url: str) -> str | None:
    response = requests.get(url)
    soup = BeautifulSoup(response.text, "html.parser")
    links = [
        a["href"]
        for a in soup.find_all("a", href=True)
        if a["href"].endswith(".img.gz")
    ]
    if not links:
        return None
    # Assuming the list is sorted by date and 
    # the last one is the most recent
    return max(links, key=lambda x: url + x)

def main():
    url_root = "https://test.libreelec.tv/13.0/RPi/RPi4/"

    if (img := latest_img(url_root)) is not None:
        print(url_root+img)
    else:
        print("No .img.gz files found.")

main()
