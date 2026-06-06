import json

with open("swagger_docs.json", "r", encoding="utf-8") as f:
    docs = json.load(f)

schemas = docs.get("components", {}).get("schemas", {})

targets = ["ForgotPasswordRequest", "ResetPasswordRequest"]

for target in targets:
    print(f"\n--- Schema: {target} ---")
    schema = schemas.get(target, {})
    print(f"Type: {schema.get('type')}")
    print("Properties:")
    properties = schema.get("properties", {})
    required = schema.get("required", [])
    for name, prop in properties.items():
        req_flag = "REQUIRED" if name in required else "OPTIONAL"
        print(f"  - {name} ({prop.get('type')}) - {req_flag}")
        if 'description' in prop:
            print(f"    Desc: {prop.get('description')}")
