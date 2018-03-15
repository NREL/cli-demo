# cli-demo
Demo of the OpenStudio CLI

Download and install [OpenStudio 2.4.0](https://github.com/NREL/OpenStudio/releases/tag/v2.4.0)

From the command line run `openstudio run -w basic_osw/in.osw`

Try out the other examples

Copy an example, modify the in.osw, and try that out

Read more about the [OpenStudio CLI](http://nrel.github.io/OpenStudio-user-documentation/reference/command_line_interface/)

Read more about [OpenStudio Measures](http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/)

## Docker Container

To run the demo within a Docker container first [install Docker](https://www.docker.com/community-edition), then run the following command:

```
cd cli-demo
docker run -v $(pwd):/var/simdata/openstudio nrel/openstudio:2.4.0 /usr/bin/openstudio run -w basic_osw/in.osw
```

The command above will download the OpenStudio docker container from [Docker Hub](https://hub.docker.com/r/nrel/openstudio/tags/), mount your local directory into the docker container, and call the OpenStudio CLI to run the basic_osw workflow.

**Note**: The OpenStudio CLI command call must be the fully qualified path to the OpenStudio CLI within the container (e.g. /usr/bin/openstudio).

**Note**: If running Docker-machine (typically on Windows 7), then you need to checkout this repo into a path within your home directory (e.g. C:\Users\username). This allows for docker to mount the files into the container since Docker-machine, by default, mounts your entire home directory into the Docker-machine VM.
