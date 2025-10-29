## COBO Agent E2E Test


1. Get the bicep
```powershell
azd init --template https://github.com/Azure-Samples/azd-ai-starter-basic
```

2. Install the required azd version and extension

Install azd daily build
```powershell
powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' -OutFile 'install-azd.ps1'; ./install-azd.ps1 -Version 'daily'"
```
Open a new powershell then
```
azd version
```
It should give you the expected commit number, most recently, you should see
```
azd version 1.20.2 (commit 2063759a9d972b4b4b8d9a5052bc4b5fa664d7e7)
```

Install extension
```powershell
azd extension install azure.foundry.ai.agents  
```
Then
```
azd ext list
```
You should see
```
Id                        Name                                  Version   Installed Version  Source
azure.coding-agent        Coding agent configuration extension  0.5.1                        azd
azure.foundry.ai.agents   AI Foundry Agents                     0.0.2     0.0.2              azd
microsoft.azd.demo        Demo Extension                        0.3.0                        azd
microsoft.azd.extensions  AZD Extensions Developer Kit          0.6.0                        azd
```

3. Init Agent sample
```
azd ai agent init -m https://github.com/coreai-microsoft/foundry-golden-path/tree/main/idea-to-proto/01-build-agent-in-code/agent-catalog-code-samples/cobo-calculator-agent
```

Your folder structure should look like this now:
```
cobo-calculator-agent/
├── .azure/
├── infra/
├── agent.yaml
├── azure.yaml
├── Dockerfile
├── langraph_agent_calculator.py
└── requirements.txt
```


4. Test
```
azd up
```
Use the following parameters if you don't have a test subscription:
```
? Select an Azure Subscription to use: 87. azure-openai-agents-exp-nonprod-01 (921496dc-987f-410f-bd57-426eb2611356)
? Enter a value for the 'aiDeploymentsLocation' infrastructure parameter: 24. (US) West US 2 (westus2)
? Enter a value for the 'enableCoboAgent' infrastructure parameter: True
```
Please contact migu@microsoft to get permission to the subscription


When it finishes, you should see console output like:
```
--- Testing Agent with Data Plane Call ---
Data Plane POST URL: https://ai-account-kply6uaglbh5u.services.ai.azure.com/api/projects/migu-cobo-int-1602/openai/responses?api-version=2025-05-15-preview
Data Plane Payload: {
  "stream": false,
  "agent": {
    "version": "2",
    "name": "Cobo Calculator Agent",
    "type": "agent_reference"
  },
  "input": "Tell me a joke."
}
Data Plane POST completed. Response:
{
  "metadata": {},
  "temperature": null,
  "top_p": null,
  "user": null,
  "model": "",
  "background": false,
  "tools": [],
  "id": "caresp_33443885792eaac0004iX4VWbkLbS4rTYxSKosWlyE6h1DZeFF",
  "object": "response",
  "status": "completed",
  "created_at": 1761349040,
  "error": null,
  "incomplete_details": null,
  "output": [
    {
      "type": "message",
      "id": "msg_33443885792eaac0009lEaLBx6qSEMnII3pakiMz10q6ZnlBVI",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "Why don't skeletons fight each other?\n\nBecause they don't have the guts!",
          "annotations": []
        }
      ]
    }
  ],
  "instructions": null,
  "parallel_tool_calls": false,
  "conversation": null,
  "agent": {
    "type": "agent_id",
    "name": "Cobo Calculator Agent",
    "version": "2"
  }
}

======================================
Azure Portal Links
======================================
Container App: https://portal.azure.com/#@/resource/subscriptions/921496dc-987f-410f-bd57-426eb2611356/resourceGroups/rg-migu-cobo-int-1602/providers/Microsoft.App/containerApps/ca-migu-cobo-int-1602-kply6uaglb  
```