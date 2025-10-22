# Azure AI Foundry `azd` starter kit (basic)

> **⚠️ Experimental Repository Notice**  
> This repository contains experimental code and configurations provided by Microsoft for demonstration and learning purposes only. It is not intended for production use and should not be deployed in production environments. Use at your own risk and discretion. The content, APIs, and functionality may change or break without notice.

<!-- WIP
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](placeholder)
[![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](placeholder)
-->

This Azure Developer CLI (azd) template provides a streamlined way to provision and deploy Azure AI Foundry resources for building and running AI agents. It includes infrastructure-as-code definitions and sample application code to help you quickly get started with Azure AI Foundry's agent capabilities, including model deployments, workspace configuration, and supporting services like storage and container hosting.

[Features](#features) • [Getting Started](#getting-started) • [Guidance](#guidance)

## Important Security Notice

This template, the application code and configuration it contains, has been built to showcase Microsoft Azure specific services and tools. We strongly advise our customers not to make this code part of their production environments without implementing or enabling additional security features.  

## Features

This project framework provides the following features:

* **Azure AI Foundry Project**: Complete setup of Azure AI Foundry workspace with project configuration
* **Foundry Model Deployments**: Automatic deployment of AI models for agent capabilities
* **Container-Based Agent Hosting**: Azure Container Apps environment for deploying and scaling AI agents
* **Azure Container Registry**: Secure container image storage and management for agent deployments
* **Storage**: Azure Storage Account with proper role-based access control for data and file management
* **Managed Identity**: Built-in Azure Managed Identity for secure, keyless authentication between services
* **Infrastructure as Code**: Complete Bicep templates for repeatable, version-controlled deployments

### Architecture Diagram

```mermaid
graph TB
    User[👤 User] --> AIF[AI Agent Runtime]
    
    subgraph "Azure Resource Group"
        subgraph "AI Foundry Workspace"
            AIF[Azure AI Foundry<br/>Project]
            AIS[Azure AI Services Resource]
            Models[Model Deployments]
        end
        
        subgraph "Container Infrastructure (Optional)"
            ACR[Azure Container Registry<br/>Agent Images]
            ACAE[Container Apps Environment]
            ACA
        end
        
        subgraph "Storage & Search (Optional)"
            Storage[Azure Storage Account<br/>Data & Files]
            Search[Azure AI Search<br/>Knowledge Base]
            Bing[Bing Search API<br/>Web Grounding]
        end
        
        subgraph "Security & Identity"
            MI[Managed Identity<br/>Keyless Auth]
            RBAC[Role-Based Access Control]
        end
    end
    
    %% Connections
    ACA --> AIF
    ACA --> Models
    AIF --> AIS
    AIF --> Storage
    AIF --> Search
    AIF --> Bing
    ACA --> ACR
    ACA --> MI
    MI --> RBAC
    ACA --> Learn
    
    %% Styling
    classDef primary fill:#0078d4,stroke:#005a9e,stroke-width:2px,color:#fff
    classDef secondary fill:#00bcf2,stroke:#0099bc,stroke-width:2px,color:#fff
    classDef optional fill:#f2f2f2,stroke:#666,stroke-width:1px,color:#333
    classDef external fill:#ffd23f,stroke:#cc9900,stroke-width:2px,color:#333
    
    class AIF,AIS,Models primary
    class ACA,ACR,ACAE secondary
    class Storage,Search,Bing optional
    class Learn external
```

This architecture shows how the Azure AI Foundry starter template creates a complete environment for AI agent development and deployment, with optional components that can be enabled based on your needs.

## Getting Started

### GitHub Codespaces

> 🚧 **Work in Progress** - GitHub Codespaces setup is currently being developed and will be available soon.

### VS Code Dev Containers

> 🚧 **Work in Progress** - VS Code Dev Containers configuration is currently being developed and will be available soon.

### Local Environment

Note: this repository is not meant to be cloned, but to be consumed as a template in your own project.

#### Prerequisites

* Install [azd](https://aka.ms/install-azd)
  * Windows: `winget install microsoft.azd`
  * Linux: `curl -fsSL https://aka.ms/install-azd.sh | bash`
  * MacOS: `brew tap azure/azd && brew install azd`

#### Quickstart

1. Bring down the template code:

    ```shell
    azd init --template Azure-Samples/ai-foundry-starter-basic
    ```

    This will perform a git clone

2. Sign into your Azure account:

    ```shell
     azd auth login
    ```

3. Add an agent... 🚧 **Work in Progress**

## Guidance

### Region Availability

This template does not use specific models. The model deployments are a parameter of the template. Each model may not be available in all Azure regions. Check for [up-to-date region availability of Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/reference/region-support) and in particular the [Agent Service](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/model-region-support?tabs=global-standard).

## Resource Clean-up

To prevent incurring unnecessary charges, it's important to clean up your Azure resources after completing your work with the application.

- **When to Clean Up:**
  - After you have finished testing or demonstrating the application.
  - If the application is no longer needed or you have transitioned to a different project or environment.
  - When you have completed development and are ready to decommission the application.

- **Deleting Resources:**
  To delete all associated resources and shut down the application, execute the following command:
  
    ```bash
    azd down
    ```

    Please note that this process may take up to 20 minutes to complete.

⚠️ Alternatively, you can delete the resource group directly from the Azure Portal to clean up resources.

### Costs

Pricing varies per region and usage, so it isn't possible to predict exact costs for your usage.
The majority of the Azure resources used in this infrastructure are on usage-based pricing tiers.

You can try the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator) for the resources deployed in this template.

⚠️ To avoid unnecessary costs, remember to take down your app if it's no longer in use, either by deleting the resource group in the Portal or running `azd down`.

### Security guidelines

This template also uses [Managed Identity](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview) for local development and deployment.

To ensure continued best practices in your own repository, we recommend that anyone creating solutions based on our templates ensure that the [Github secret scanning](https://docs.github.com/code-security/secret-scanning/about-secret-scanning) setting is enabled.

You may want to consider additional security measures, such as:

- Enabling Microsoft Defender for Cloud to [secure your Azure resources](https://learn.microsoft.com/azure/defender-for-cloud/).
- Protecting the Azure Container Apps instance with a [firewall](https://learn.microsoft.com/azure/container-apps/waf-app-gateway) and/or [Virtual Network](https://learn.microsoft.com/azure/container-apps/networking?tabs=workload-profiles-env%2Cazure-cli).

> **Important Security Notice** <br/>
This template, the application code and configuration it contains, has been built to showcase Microsoft Azure specific services and tools. We strongly advise our customers not to make this code part of their production environments without implementing or enabling additional security features.  <br/><br/>
For a more comprehensive list of best practices and security recommendations for Intelligent Applications, [visit our official documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/).

### Resources

This template creates everything you need to get started with Azure AI Foundry:

| Resource | Description |
|----------|-------------|
| [Azure AI Foundry](https://learn.microsoft.com/azure/ai-foundry) | Provides a collaborative workspace for AI development with access to models, data, and compute resources |
| [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/) | Hosts and scales the web application with serverless containers |
| [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/) | Stores and manages container images for secure deployment |
| [Storage Account](https://learn.microsoft.com/azure/storage/blobs/) | Provides blob storage for application data and file uploads |
| [AI Search Service](https://learn.microsoft.com/azure/search/) | *Optional* - Enables hybrid search capabilities combining semantic and vector search |
| [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview) | *Optional* - Provides application performance monitoring, logging, and telemetry for debugging and optimization |
| [Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview) | *Optional* - Collects and analyzes telemetry data for monitoring and troubleshooting |

## Disclaimers

To the extent that the Software includes components or code used in or derived from Microsoft products or services, including without limitation Microsoft Azure Services (collectively, “Microsoft Products and Services”), you must also comply with the Product Terms applicable to such Microsoft Products and Services. You acknowledge and agree that the license governing the Software does not grant you a license or other right to use Microsoft Products and Services. Nothing in the license or this ReadMe file will serve to supersede, amend, terminate or modify any terms in the Product Terms for any Microsoft Products and Services.

You must also comply with all domestic and international export laws and regulations that apply to the Software, which include restrictions on destinations, end users, and end use. For further information on export restrictions, visit <https://aka.ms/exporting>.

You acknowledge that the Software and Microsoft Products and Services (1) are not designed, intended or made available as a medical device(s), and (2) are not designed or intended to be a substitute for professional medical advice, diagnosis, treatment, or judgment and should not be used to replace or as a substitute for professional medical advice, diagnosis, treatment, or judgment. Customer is solely responsible for displaying and/or obtaining appropriate consents, warnings, disclaimers, and acknowledgements to end users of Customer’s implementation of the Online Services.

You acknowledge the Software is not subject to SOC 1 and SOC 2 compliance audits. No Microsoft technology, nor any of its component technologies, including the Software, is intended or made available as a substitute for the professional advice, opinion, or judgement of a certified financial services professional. Do not use the Software to replace, substitute, or provide professional financial advice or judgment.  

BY ACCESSING OR USING THE SOFTWARE, YOU ACKNOWLEDGE THAT THE SOFTWARE IS NOT DESIGNED OR INTENDED TO SUPPORT ANY USE IN WHICH A SERVICE INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE COULD RESULT IN THE DEATH OR SERIOUS BODILY INJURY OF ANY PERSON OR IN PHYSICAL OR ENVIRONMENTAL DAMAGE (COLLECTIVELY, “HIGH-RISK USE”), AND THAT YOU WILL ENSURE THAT, IN THE EVENT OF ANY INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE, THE SAFETY OF PEOPLE, PROPERTY, AND THE ENVIRONMENT ARE NOT REDUCED BELOW A LEVEL THAT IS REASONABLY, APPROPRIATE, AND LEGAL, WHETHER IN GENERAL OR IN A SPECIFIC INDUSTRY. BY ACCESSING THE SOFTWARE, YOU FURTHER ACKNOWLEDGE THAT YOUR HIGH-RISK USE OF THE SOFTWARE IS AT YOUR OWN RISK.