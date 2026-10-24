import urllib.request
import json
import os
import re

os.makedirs('stitch_designs', exist_ok=True)

with open('stitch_screens.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

content_text = data['result']['content'][0]['text']
parsed = json.loads(content_text)

for s in parsed['screens']:
    raw_title = s.get('title', 'screen')
    clean_title = re.sub(r'[^\w\s-]', '', raw_title).strip()[:40].replace(' ', '_')
    screen_id = s['name'].split('/')[-1]
    
    html_info = s.get('htmlCode', {})
    download_url = html_info.get('downloadUrl')
    if download_url:
        try:
            req = urllib.request.Request(download_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as resp:
                content = resp.read().decode('utf-8')
                filename = os.path.join('stitch_designs', f"{clean_title}.html")
                with open(filename, 'w', encoding='utf-8') as out_f:
                    out_f.write(content)
                print(f"Saved HTML: {filename}")
        except Exception as e:
            print(f"Failed to download {clean_title}: {e}")

    # Also save screenshot URL and metadata
    screenshot_info = s.get('screenshot', {})
    if screenshot_info.get('downloadUrl'):
        print(f"Screenshot for {clean_title}: {screenshot_info.get('downloadUrl')[:60]}...")
