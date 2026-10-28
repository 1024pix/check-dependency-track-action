# Pix Action Dependency-Track Check

This Github action generates a BoM (Bill Of Materials) of your project and uploads it to an OWASP Dependency Track instance to perform a vulnerability check. In order to use it, you will need an OWASP Dependency Track instance and an access Key to be able to use the REST API from Internet. 

One of the main advantages is that you can customize the vulnerability check sources Dependency Track will use, you can easily check the project status of the different versions using the Dependency Track WUI and you can also check the licenses of the different libraries you project is using. 

The project will be uploaded to the OWASP Dependency Track server using the repository name as `project` and the branch or tag name as `version`. Its **BoM Format**, no matter which language it is, will be **v1.5**, supported by Dependecy Track v4.0.0 and higher. The conversion is made possible thanks to [CycloneDX CLI](https://github.com/CycloneDX/cyclonedx-cli) convert tool, which generates v1.2 BoM Formats both from languages plugins/modules which yet do not generate v1.2 BoM Formats, as well as from those languages which just generate v1.3 BoM Formats (not supported by our DT version). 

## Fork history

This repo is a hard fork from https://github.com/Quobis/action-owasp-dependecy-track-check. The Quobis action is more generic (it supports Ruby, Maven, NuGet and PHP) with is not necessary for us.

It doesnt support basic auth on dependency-track, monorepo, and dynamic nodejs versions.

## TODO 

* [x] use pinned versions of cyclonedx-npm
* [x] use specific versions of npm
* [x] language : node
* [ ] wire `omit_devdependencies`
* [ ] query dependency-track with basic auth
* [ ] language : python
* [ ] language : go (go install github.com/CycloneDX/cyclonedx-gomod/cmd/cyclonedx-gomod@latest / cyclonedx-gomod app -json .)

## Implementation plan

Proposed structure (one repo, three actions, one shared script)

```
action-dependency-track-pix/
├── node/action.yml      # setup-node → npm ci --ignore-scripts → cyclonedx-npm --package-lock-only
├── python/action.yml    # setup-python → cyclonedx-py requirements|poetry|pipenv
├── go/action.yml        # setup-go → cyclonedx-gomod (replaces archived ozonru/cyclonedx-go)
└── scripts/upload.sh    # upload + polling + risk score (the current end of entrypoint.sh)
Usage: uses: 1024pix/dtrack-action/node@<sha>
```

- One repo means one version, one CI and the same upload logic for every language.
- A common gotcha: inside a composite action, uses: ./something resolves against the calling repo, not yours. Call the shared script with run: ${{ github.action_path }}/../scripts/upload.sh instead.
- Pin actions/setup-* by SHA inside your actions.
- Trade-off: composite actions run directly on the runner, not in a container. The global npm i -g / pip install affect the job's environment. That's fine on GitHub-hosted runners, which are thrown away after each job.

## Input variables

This action requires these input variables:
- **url**: URL of the OWASP Dependency Track server
- **key**: KEY used to access the OWASP Dependency Track server, please not that this must no be appropiate for public repositories. 
  * This key is confidencial information, so we recommend to [create a secret](https://docs.github.com/en/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository) in the project settings. In the action example we use the name `SECRET_OWASP_DT_KEY` for this secret.
  * Scopes needed : BOM_UPLOAD, PROJECT_CREATION_UPLOAD, VIEW_PORTFOLIO
- **language**: (refer to the next section)
- **directory**: (optional) for monorepos, dependencies may be defined in a sub-directory. Defautl = `.`
- **node_version**: (optional) version for node
- **basic_user**: (optional) for basic auth in Dependency Track
- **basic_password**: (optional) for basic auth in Dependency Track

## Output variables

- **riskscore**: this variable will contain the risk score calculated by OWASP Dependency Track based on the found vulnerabilities. This output can be used to make decision such as notify the developer or use it as the input of the next step of the workflow.

## Supported languages

Currently this action supports the generation of upload of projects devloped in the languages as follows:

- **Node.js**: define the language variable as `npm` or `npm-ci`. `npm install` will be executed within the container to gather all the dependencies or the package-lock file will be used.  
- **Python**: define the language variable as `python`. It will get the package information from requirements.txt. 
- **Golang**: define the language variable as `golang`. It will get the package information from go.mod, which is typically present in the repository.


Please note that if any of the files above is not available the action will fail when trying to generate the BoM files. 


## How to use it

### Step 1: Get your Dependency Track both URL and Key

This will let you use the API to upload your projects' bom.xml from this GitHub action.
+ How to get your Key. Go to Configuration -> Teams -> Create Team to create a new team. This will also create a corresponding API Key, although a team might have multiple Keys. You can find more info about this [here](https://docs.dependencytrack.org/integrations/rest-api/). 

Scopes needed : BOM_UPLOAD, PROJECT_CREATION_UPLOAD, VIEW_PORTFOLIO, nothing else.

### Step 2: Set up your action.yml file

+ Start by creating a `.github/workflows` directory in your repository if it doesn't already exist.
+ In this directory, create a file named `owasp-dt-check.yml`.
+ Copy the example shown below into your `owasp-dt-check.yml` file:
  
```yaml
# This is a basic workflow to help you get started with Actions

name: CI

# Controls when the action will run. 
on: [push]

  # Allows you to run this workflow manually from the Actions tab
  # workflow_dispatch:

# A workflow run is made up of one or more jobs that can run sequentially or in parallel
jobs:
  # This workflow contains a single job called "build"
  build:
    # The type of runner that the job will run on
    runs-on: ubuntu-latest

    # Steps represent a sequence of tasks that will be executed as part of the job
    steps:
      # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
      - uses: actions/checkout@v7 # a better security practice would be to pin the commit sha
      
      # Generates a BoM and uploads it to OWASP Dependency Track
      - name: Generates BoM and upload to OWASP DTrack
        id: riskscoreFromDT
        uses:  1024pix/action-dependecy-track-pix@main # a better security practice would be to pin the commit sha
        with:
          url: 'https://dtrack.quobis.com'
          key: '${{ secrets.SECRET_OWASP_DT_KEY }}'
          language: 'golang'
      
      # Show the risk score output 
      - name: Get the output time
        run: echo "The risk score of the project is ${{ steps.upload.outputs.riskscore }}"
```

Don't forget to change the `url` `key` and `language` according to your project and Dependecy Track server. As you can see, we're using a secret to save our DT's user valid key. We strongly recommend you to do so.

We also added an example of the `yaml` file which can be included in the workflow to use this action. You can find the file `example-action.yaml` in this repository.

+ Commit changes to your repository `.workflow` directory. Once you finish don't forget to save and commit. This will trigger the workflow is first run as it's configure to start on every push, and you'll be able to see the resault in your Dependency Track server.

