import os
import whois
from concurrent.futures import ThreadPoolExecutor
from tqdm import tqdm

def check_domain_availability(domain):
    try:
        info = whois.whois(domain, timeout=10)
        return not bool(info.domain_name)
    except (whois.parser.PywhoisError, TimeoutError) as e:
        print(f"查询域名 {domain} 时发生错误：{e}")
        return False

def generate_domain_names(length, suffix=".com"):
    import itertools
    import string

    alphabet = string.ascii_lowercase
    domains = [''.join(combination) for combination in itertools.product(alphabet, repeat=length)]
    domains = [domain + suffix for domain in domains]

    return domains

def save_available_domains_to_file(domains, output_file):
    desktop_path = os.path.join(os.path.expanduser("~"), "Desktop")
    file_path = os.path.join(desktop_path, output_file)

    with open(file_path, 'w') as file:
        with ThreadPoolExecutor() as executor:
            results = list(tqdm(executor.map(check_domain_availability, domains), total=len(domains), desc="生成域名进度", unit="域名"))
            for domain, result in zip(domains, results):
                if result:
                    file.write(domain + '\n')

if __name__ == "__main__":
    domain_length = int(input("请输入域名长度（6位数以下）: "))
    suffix = input("请输入域名后缀（例如.com）: ") or ".com"
    output_file = "com.txt"

    domains = generate_domain_names(domain_length, suffix)
    save_available_domains_to_file(domains, output_file)

    print(f"查询完成，结果保存在桌面的 '{output_file}' 文件中。")
