#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <stdio.h>
#include <errno.h>

#define me argv[0]

#define hint "Use -h para obtener ayuda"

#define true  1
#define false 0

#define SHELL "/bin/sh"
#define OFFSET 2
#define FEED "\n"

typedef int boolean;

void
help (const char *program)
{
	printf (
		FEED
		"Uso:\n"
		FEED
		"%s ((--help|-h) | (--file|-f|--input|-i) INPUT (--output|-o) OUTPUT [(--offset|-O) OFFSET]\n"
		"  [(--shell|-s) SHELL] [(--debug|-d)])\n"
		FEED
		"Parámetros:\n"
		FEED
		"--help|-h                   Escribe este texto de ayuda. Imagínese por qué.\n"
		"--file|-f|--input|-i INPUT  El script a compilar.\n"
		"--output|-o OUTPUT          El archivo binario a generar.\n"
		"--offset|-O                 El desplazamiento de bytes (no bits) para ofuscar el código.\n"
		"                            El valor por omisión es 2. Úselo con cuidado.\n"
		"--shell|-s SHELL            El shell a invocar en el binario. El shell por omisión es /bin/sh."
		"--debug                     En lugar de eliminar el archivo C intermedio imprime el nombre en la salida.\n"
		FEED, program);
}

void
error (const char *message)
{
	fprintf (stderr, "%s. %s.\n", message, hint);
}

int
main (int argc, char *argv[])
{
	FILE *input_fd = NULL;
	FILE *output_fd = NULL;

	char *tmp_output = NULL;
	char *buffer = NULL;
	char *command = NULL;
	char *input = NULL;
	char *output = NULL;
	char *shell = SHELL;

	int offset = OFFSET;
	int current_option = -1;
	int size = 1;
	int byte;

	boolean debug = false;

	const struct option options[] = {
		{ "file"  , 1, NULL, 'f' },
		{ "output", 1, NULL, 'o' },
		{ "input" , 1, NULL, 'i' },
		{ "shell" , 1, NULL, 's' },
		{ "offset", 1, NULL, 'O' },
		{ "debug" , 0, NULL, 'd' },
		{ "help"  , 0, NULL, 'h' },
		{  NULL   , 0, NULL,  0  }
	};

	do
	{
		current_option = getopt_long (argc, argv, "f:o:i:s:O:dh", options, NULL);

		switch (current_option)
		{
			case 'i':
			case 'f':
				input = optarg;
				break;

			case 'o':
				output = optarg;
				break;

			case 's':
				shell = optarg;
				break;

			case 'O':
				offset = atoi (optarg); /* todo */
				break;

			case 'h':
				help (me);
				exit (EXIT_SUCCESS);

			case 'd':
				debug = true;
				break;

			case -1:
				break;
	
			default:
				error ("Faltan argumentos o son inválidos");
				exit (EXIT_FAILURE);
		}
	} while (current_option != -1);

	if (!input)
	{
		error ("Por favor, especifique el script a compilar");
		exit (EXIT_FAILURE);
	}

	if (!output)
	{
		error ("Por favor, especifique el binario que desea generar");
		exit (EXIT_FAILURE);
	}

	if (access (input, R_OK) == -1)
	{
		perror ("Error");
		exit (EXIT_FAILURE);
	}

	input_fd = fopen (input, "r");

	if (!input_fd)
	{
		perror ("Error");
		exit (EXIT_FAILURE);
	}

	buffer = (char *) malloc (sizeof (char));

	while ((byte = fgetc (input_fd)) != EOF)
	{
		buffer = realloc (buffer, size + 4);
		sprintf (buffer+size-1, "\\x%02x", byte + offset);
		size += 4;
	}

	fclose (input_fd);

	tmp_output = malloc (sizeof (char) * 256);
	sprintf (tmp_output, "%s.c", tmpnam (NULL));
	tmp_output = realloc (tmp_output, sizeof (char) * strlen (tmp_output));

	output_fd = fopen (tmp_output, "w");

	if (!output_fd)
	{
		perror ("Error de fopen");
		exit (EXIT_FAILURE);
	}

	fprintf (output_fd, "#include <unistd.h>\n#include <stdlib.h>\n#include <string.h>\n#include <stdio.h>\n");
	fprintf (output_fd, "const char source[%d]=\"%s\";", size - 1, buffer);
	fprintf (output_fd, "char*unserialize(char*string){int i,size=strlen(string);");
	fprintf (output_fd, "char*buffer=malloc(sizeof(char)*size);for(i=0;i<size;i++)buffer[i]=string[i]-%d;", offset);
	fprintf (output_fd, "buffer[size]='\\0';return buffer;}");
	fprintf (output_fd, "int main(int argc,char*argv[]){char*output=tmpnam(NULL);FILE*script=fopen(output,\"w\");");
	fprintf (output_fd, "char*tmp=unserialize((char*)source);fprintf(script,\"%%s\",tmp);fflush(script);");
	fprintf (output_fd, "free(tmp);fclose(script);char*command=malloc(sizeof(char));");
	fprintf (output_fd, "command=realloc(command,sizeof(char)*strlen(output)+%d+1);", strlen (shell));
	fprintf (output_fd, "sprintf(command,\"%s %%s\", output);", shell);
	fprintf (output_fd, "int arg,size=strlen(command);for(arg=1;arg<argc;arg++){");
	fprintf (output_fd, "command=realloc(command,sizeof(char)*(size+strlen(argv[arg])+2));");
	fprintf (output_fd, "sprintf(command+size,\" %%s\",argv[arg]);");
	fprintf (output_fd, "size=strlen(command);}command[size]='\\0';int status=system(command);");
	fprintf (output_fd, "free(command);unlink(output);exit(status);}");
	
	fflush (output_fd);
	fclose (output_fd);
	free (buffer);

	command = malloc (sizeof (char) * (8 + 1 + strlen (tmp_output) + strlen (output)));
	sprintf (command, "gcc %s -o %s", tmp_output, output);
	system (command); /* int status = system (command); */
	free (command);

	if (debug)
		printf ("El archivo C intermedio es %s.\n", tmp_output);
	else
		unlink (tmp_output); /* int success = unlink (const char *pathname); */

	exit (EXIT_SUCCESS);
}
