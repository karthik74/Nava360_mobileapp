import json

with open("swagger_docs.json", "r", encoding="utf-8") as f:
    docs = json.load(f)

paths = docs.get("paths", {})

targets = ["/api/auth", "/api/leaves", "/api/attendance", "/api/tasks", "/api/users/me"]

print("Target Endpoint Structures:")
for target in targets:
    print(f"\n--- {target} ---")
    for path, methods in sorted(paths.items()):
        if path.startswith(target) or path == target:
            for method, details in methods.items():
                print(f"{method.upper()} {path}")
                # print parameters
                if 'parameters' in details:
                    print("  Params:")
                    for p in details['parameters']:
                        print(f"    - {p.get('name')} ({p.get('in')}): {p.get('schema', {}).get('type')}")
                # print request body
                if 'requestBody' in details:
                    print("  RequestBody:")
                    content = details['requestBody'].get('content', {})
                    for ct, ct_details in content.items():
                        ref = ct_details.get('schema', {}).get('$ref', '')
                        if not ref and 'items' in ct_details.get('schema', {}):
                            ref = ct_details['schema']['items'].get('$ref', 'array of primitive')
                        print(f"    - {ct}: {ref or ct_details.get('schema', {}).get('type')}")
                # print responses
                if 'responses' in details:
                    print("  Responses:")
                    for status, resp in details['responses'].items():
                        ref = ""
                        if 'content' in resp:
                            for ct, ct_details in resp['content'].items():
                                ref = ct_details.get('schema', {}).get('$ref', '')
                                if not ref and 'items' in ct_details.get('schema', {}):
                                    ref = ct_details['schema']['items'].get('$ref', 'array of primitive')
                                break
                        print(f"    - {status}: {ref or 'empty'}")
