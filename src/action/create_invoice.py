import requests
import json
from base64 import b64encode
from Crypto.Signature import pkcs1_15
from Crypto.Hash import SHA512
from Crypto.PublicKey import RSA
from datetime import datetime

# Konfiguráció
api_url = "https://api-test.onlineszamla.nav.gov.hu/invoiceService/v3"
user = "YOUR_USER"
password = "YOUR_PASSWORD"
signing_key = "YOUR_SIGNING_KEY"
exchange_key = "YOUR_EXCHANGE_KEY"

# Aláírás generálása
def generate_signature(request_id, timestamp, signing_key):
    signature_string = f"{request_id}|{timestamp}"
    key = RSA.import_key(signing_key)
    h = SHA512.new(signature_string.encode('utf-8'))
    signature = pkcs1_15.new(key).sign(h)
    return b64encode(signature).decode('utf-8')

# Kérés fejléc
def get_request_header(request_id):
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3] + "Z"
    signature = generate_signature(request_id, timestamp, signing_key)
    return {
        "Content-Type": "application/json",
        "X-API-KEY": exchange_key,
        "X-USER-NAME": user,
        "X-PASSWORD": password,
        "X-REQUEST-ID": request_id,
        "X-TIMESTAMP": timestamp,
        "X-SIGNATURE": signature
    }

# Számla adatok (ez csak egy egyszerűsített példa)
invoice_data = {
    "invoiceNumber": "2024/00001",
    "invoiceIssueDate": "2024-10-10",
    "supplierTaxNumber": "12345678-1-11",
    "supplierName": "Példa Kft.",
    "customerTaxNumber": "87654321-2-22",
    "customerName": "Vásárló Bt.",
    "items": [
        {
            "lineNumber": "1",
            "lineDescription": "Termék 1",
            "quantity": 2,
            "unitOfMeasure": "db",
            "unitPrice": 1000,
            "lineAmountHUF": 2000
        }
    ],
    "invoiceCategory": "NORMAL",
    "paymentMethod": "TRANSFER",
    "invoiceAppearance": "ELECTRONIC",
    "currencyCode": "HUF",
    "exchangeRate": 1,
    "invoiceDeliveryDate": "2024-10-10"
}

# Kérés küldése
def send_invoice(invoice_data):
    request_id = "RID" + datetime.now().strftime("%Y%m%d%H%M%S%f")
    headers = get_request_header(request_id)
    payload = {
        "exchangeToken": exchange_key,
        "invoiceData": json.dumps(invoice_data)
    }
    response = requests.post(f"{api_url}/invoiceApi/manageInvoice", headers=headers, json=payload)
    return response.json()

# Számla küldése
result = send_invoice(invoice_data)
print(json.dumps(result, indent=2))