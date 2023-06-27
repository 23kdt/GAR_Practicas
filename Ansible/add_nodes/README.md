## Añadir nodos al inventario
Si queremos añadir nodos, pero sin eliminar el contenido del inventario (ya que eliminaría el resto de hosts asociados), puede ser de utilidad el siguiente código. Hay que tener en cuenta que un host puede pertenecer a distintos host_groups, por lo que tanto la IP y la MAC pueden estar repetidas en varios host_groups, pero no puede haber dos host iguales en un mismo host_group, ya que estaría duplicado. 

Deberemos configurar los certificados ssh para poder ejecutar los nodos remotos desde el nodo de control.

Crearemos un script en bash para copiar las claves ssh en todos los hosts remotos:

```
#!/bin/bash

# Variables
ssh_key_file="/home/kdt23/.ssh/ansible.pub"
inventory_file="inventario"

# Iterar sobre las direcciones IP del archivo inventario
grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' $inventory_file | while read ip_address; do
  # Ejecutar ssh-copy-id
  output=$(sshpass -f /home/kdt23/.password.txt ssh-copy-id -i $ssh_key_file $ip_address 2>&1) # Redireccionar stderr a stdout
  if echo "$output" | grep -q "WARNING: All keys were skipped"; then
    echo "La clave ya existe en $ip_address, se omite"
  else
    echo "La clave se ha añadido correctamente en $ip_address"
  fi
done


```

Brevemente, explico este código:

Almacenamos como variables las rutas al archivo dónde almacenamos las claves ssh y la ruta dónde almacenamos el inventario con todos los hosts asociados.
A continuación, mediante el comando grep, iteramos sobre todas las líneas del inventario y sobre cada IP realizamos el comando ``sshpass -f /home/kdt23/.password.txt ssh-copy-id -i $ssh_key_file $ip_address``. Este comando lo que hace es pasar la clave ssh a los nodos remotos (mediante ssh-copy-id) y mediante ``sshpass -f`` lo que indicamos será las claves de dichos nodos remotos, para evitar que nos pregunte por ellas y automatizar el proceso. Además, redirigimos la señal a la salida estándar con el fin de capturar excepciones (en caso de que el host remoto ya tenga la clave púbica en su carpeta **authorized_keys**).  

Este fichero deberá ejecutarse desde el nodo de control para que se aplique sobre el resto de nodos. Para ello, podemos hacer uso del parámetro **script** o **command** en las tareas de los playbook. 
Para ello, hemos creado otro play dentro del playbook anterior de añadir nodos:

## Add_nodos.yaml

```
#Archivo add_nodos.yaml

- name: Añadir host al inventario
  hosts: localhost
  gather_facts: false
  vars:
    inventory_file: "inventario"
  tasks:
    - name: Leer archivo de nodos
      set_fact:
        nodos: "{{ lookup('file', 'nodos.yaml') | from_yaml }}"
        wantlist: True
      no_log: true

    - name: Añadir host al inventario
      add_host:
        name: "{{ item.ip_address }}"
        ansible_host: "{{ item.ip_address }}"
        mac_address: "{{ item.mac_address }}"
        node_role: "{{ item.node_role }}"
      delegate_to: localhost
      loop: "{{ nodos }}"

    - name: Validar si existe el grupo en el archivo de inventario
      shell: grep -q "\[{{ item.node_role }}\]" {{ inventory_file }}
      ignore_errors: true
      changed_when: false
      failed_when: false
      register: group_exist
      loop: "{{ nodos }}"

    - name: Establecer group_exist en caso de que grep falle
      set_fact:
        group_exist: "{{ {'rc': 1} if group_exist is failed else group_exist }}"
      loop: "{{ nodos }}"

    - name: Añadir entrada de host al archivo de inventario si no existe el grupo
      lineinfile:
        path: "{{ inventory_file }}"
        line: "\n[{{item.node_role}}]\n{{ item.ip_address }} ansible_mac_address={{ item.mac_address }}"
        insertafter: EOF
      when: item in group_exist.results | selectattr('rc','eq', 1) | map(attribute='item') | list
      delegate_to: localhost
      loop: "{{ nodos }}"

    - name: Añadir entrada de host al archivo de inventario si existe el grupo
      lineinfile:
        path: "{{ inventory_file }}"
        line: "{{ item.ip_address }} ansible_mac_address={{ item.mac_address }}"
        insertafter: "\\[{{ item.node_role }}\\]"
        state: present
      when: item in group_exist.results | selectattr('rc','eq', 0) | map(attribute='item') | list
      delegate_to: localhost
      loop: "{{ nodos }}"


- name: SSH
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Asociar claves SSH
      script: sh_ssh_nodos.sh
      delegate_to: localhost



- name: Añadir nuevos nodos al host_group nuevos
  hosts: localhost
  gather_facts: false
  vars:
    inventory_file: "inventario"
  tasks:
    - name: Leer archivo de nodos
      set_fact:
        nodos: "{{ lookup('file', 'nodos.yaml') | from_yaml }}"
        wantlist: True
      no_log: true

    - name: Añadir host al inventario
      add_host:
        name: "{{ item.ip_address }}"
        ansible_host: "{{ item.ip_address }}"
        mac_address: "{{ item.mac_address }}"
        node_role: "{{ item.node_role }}"
      delegate_to: localhost
      loop: "{{ nodos }}"
   
    - name: Crear host_group nuevos
      lineinfile:
        path: "{{ inventory_file }}"
        line: "\n[nuevos]\n"
        insertafter: EOF
      delegate_to: localhost


    - name: Añadir nodos al host_group nuevos
      lineinfile:
        path: "{{ inventory_file }}"
        line: "{{ item.ip_address }} ansible_mac_address={{ item.mac_address }} node_role={{ item.node_role }}"
        insertafter: "[nuevos]"
        state: present
      delegate_to: localhost
      loop: "{{ nodos }}"

```



Vamos a explicar brevemente este codigo:

En primer lugar, creamos un play que se encargará de añadir los nuevos nodos al archivo de inventario, para evitar manejarlo directamente y evitar posibles errores que pueden ocurrir al hacerlo manualmente en entornos algo más avanzados o con gran cantidad de nodos. Para ello, tomará como referencia el archivo "nodos.yaml", un manifiesto donde indicamos los nodos que queremos crear, así como su IP, MAC y rol.
Mediante la primera tarea, crearemos una lista de nodos a partir del archivo anterior, para después añadirlo al inventario de memoria (que no el archivo como tal) mediante el uso de bucles sobre la lista creada anteriormente. 
Es importante matizar que en un inventario, un host puede pertenecer a varios grupos, ya que puede ocuparse de distintas funcionalidades distintas, por lo que no podemos únicamente reemplazar la entrada anterior por una nueva. Además, tampoco podemos crear una entrada para cada node_role de los nodos a añadir, ya que seguramente dichas entradas de host_group ya tengan algún host asociado y no tendría sentido tener varios host_group que se refieran al mismo rol. 
Por ello, debemos utilizar el comando grep para ver si el node_role (que nos servirá como identificador del grupo para simplificar la práctica) ya existe dentro del archivo de inventario. El resultado se almacenará en el diccionario group_exist. También debemos crear una tarea por si acaso no el grupo no existiera, poniendo el valor de la variable rc del diccionario a 1. 

Las siguientes tareas se encargarán de comprobar si el valor de rc es 1 o 0 para cada item de la lista de nodos, para así únicamente añadir aquel nodo que cumpla con dicha variable, y no todos los nodos. 
En estas tareas también se escribirá en el archivo de inventario, teniendo en cuenta si se tiene que añadir una entrada nueva para el host_group o únicamente añadirlo a este en caso de que ya exista. 

La tarea "SSH":
```
- name: SSH
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Asociar claves SSH
      script: sh_ssh_nodos.sh
      delegate_to: localhost
```

Se encarga de ejecutar el script mostrado anteriormente. 
