Param
(
    [Parameter(Mandatory = $true)]
    [String]$DefinitionName,
    [String]$BuildNumber  = 1
)
###test1
Write-Output "########################### Inicio do Build $BuildNumber ###########################"
$dir_root = Get-Location
$getchilditem= Get-ChildItem src -Recurse -Name
[array]::Reverse($getchilditem)
$db_files="db_files.sql"
$rollback_file="rollback.sql"
$temp_db_files="temp-lista-exec-scripts-$DefinitionName-$BuildNumber.sql"
$temp_rollback_file="temp-lista-exec-rollback-$DefinitionName-$BuildNumber.sql"


#Valida se os arquivos DB_FILES.SQL e ROLLBACK.SQL existem
#Retorna 1 quando o arquivo nao existe 
#Retorna 0 quando o arquivo existe 
function fileExist([string]$myfile) {

	if(Test-Path $myfile) {
		return 0
	}
	if($myfile -eq $db_files){
		#Erro no db_files.sql mata a execução
		Write-Error -Exception "Arquivo nao encontrado" -Message "######## Arquivo $myfile nao encontrado!!"
		exit 1
	}
	#erro nos demais arquivos apenas retornar erro (1)
	return 1
}

#Valida os arquivos DB_FILES.SQL e ROLLBACK.SQL
#Retorna 1 quando o arquivo é invalido
function validateFiles([string]$file) {

	$f = fileExist($file)
	if($f -eq 1){
		return 1		
	}

	$erro=0
	$temp_file = $temp_db_files

	Get-Content $file | ForEach-Object {
	
		#valida linha vazia
		if($_ -eq ""){
			return
		}
		
		$file_row = $_.replace("/","\") 

		#valida comentario
		if($_.length -gt 2){
			$comment = $file_row.Substring(0,2)
			if($comment.StartsWith("--")){
				return
			}
		}	
				
		#Valida diretorios
		if(-Not ($file_row.contains("src\main\resources\db\"))){
			Write-Warning "######## Estrutura de diretorio incorreta: $file_row" 
			$erro++
			return
		}
		
		#Valida extensao
		if(-Not ($file_row.EndsWith(".sql") -Or $file_row.EndsWith(".SQL"))){ 
			Write-Warning "######## Extensao do arquivo incorreta: $file_row" 
			$erro++
			return
		}

		#Valida se arquivo esta versionado
		if(-Not (Test-Path -Path $file_row)){ 
			Write-Warning "######## Arquivo $file_row nao esta versionado no Git" 
			$erro++
			return
		}		
		
		$file_row = $file_row.replace("src\main\resources\db\","")

		if($file -eq $rollback_file){
			$temp_file = $temp_rollback_file
		}

		Write-Output "$file_row" | Out-File -Encoding UTF8 -Append $temp_file
	}
	
	#validate temp_files
	$quantity_files = 0
	$quantity_temp_file = 0

	Get-Content $temp_file | ForEach-Object {

		$quantity_temp_file++
		foreach ($row in $getchilditem) {
			$new_row = $row.replace("main\resources\db\","")
			if($_ -ceq $new_row){
				$quantity_files++
			}
		} 
		
		if($quantity_files -ne $quantity_temp_file){
			Write-Warning "######## Arquivo $_ esta versionado com o nome diferente do que esta no db_files.sql (ou rollback.sql)" 
			$erro++
			#iguala para nao repetir o erro em todos os itens do loop
			$quantity_files = $quantity_temp_file
		}
	}

	if($erro -eq 0){
		Write-Output "######## $file validado com sucesso!"
		return 0
	}
	
	#Arquivo invalido, fim da execucao
	Remove-Item $temp_file
	Write-Error -Exception "O arquivo $file esta incorreto" -Message "Existem $erro linhas invalidas."
	exit 1
}

#Criar a estrutura de pastas e subpastas, esta estrutura pode ser dos scripts executados, backup ou rollback 
function createFoldersStructure([string]$structure){

	if(-Not ($structure -eq "script" -or $structure -eq "backup" -or $structure -eq "rollback")){
		Write-Error -Exception "Erro na criacao de pastas" -Message "######## Nao e possivel criar as pastas, estrutura invalida"
		exit 1
	}

	if($structure -eq "script"){
		$dir_temp = "$dir_root\script"
		$temp_file = $temp_db_files
	}
	if($structure -eq "backup"){
		$dir_temp = "$dir_root\backup"
		$temp_file = $temp_db_files
	}
	if($structure -eq "rollback"){
		$dir_temp = "$dir_root\rollback"
		$temp_file = $temp_rollback_file
	}
	New-Item -ErrorAction Ignore -ItemType directory -Path $dir_temp | Out-Null	

	Set-Location $dir_root
	Get-Content $temp_file | ForEach-Object {
		$dir_end = $_.indexOf("\")
		$dir_name = $_.Substring(0,$dir_end)
		Set-Location $dir_temp
		New-Item -ErrorAction Ignore -ItemType directory -Path $dir_name | Out-Null
		
		#Existe subdiretorio
		if($_.indexOf("\") -ne $_.LastIndexOf("\")){
			$str_file_name_size = $_.LastIndexOf("\") - $_.indexOf("\") - 1
			$subdir_name = $_.Substring($_.indexOf("\")+1,$str_file_name_size)
			Set-Location $dir_name
			New-Item -ErrorAction Ignore -ItemType directory -Path $subdir_name | Out-Null
			Set-Location ..
			New-Item -ErrorAction Ignore -ItemType directory -Path $dir_name | Out-Null						
		}		
		Set-Location $dir_root
	}
}

#Copiar para a estrutura de pastas os arquivos SQL que serao executados
function copyFilesToFolders([string]$structure) {

	if(-Not ($structure -eq "script" -or $structure -eq "rollback" -or $structure -eq "backup")){
		Write-Error -Exception "Erro na copia dos arquivos " -Message "######## Nao e possivel copiar arquivos, estrutura invalida"
		exit 1
	}
	if($structure -eq "script"){
		$temp_file = $temp_db_files
		$has_prefix = "script\"
	}
	if($structure -eq "backup"){
		$temp_file = $temp_db_files
		$has_prefix = "backup\"
	}
	if($structure -eq "rollback"){
		$temp_file = $temp_rollback_file
		$has_prefix = "rollback\"
	}

	Set-Location $dir_root
	Get-Content $temp_file | ForEach-Object {
		$origin = "src\main\resources\db\"+$_
		$destin = $has_prefix+$_		
		if($structure -eq "backup"){
			$file_name = getFileName($destin)
			$file_name = $file_name+".tmp"
			$folder_name = getFolderName($destin)
			New-Item -ErrorAction Ignore -Path $folder_name -Name $file_name -ItemType "file" -Value " " | Out-Null	
		}else{
			Copy-Item -Path $origin -Destination $destin
		}
	}
} 

#Gera o arquivo chamador
function createScriptCaller() {

	$error = validateFiles($db_files)
	if ($error -eq 1){
		Write-Output "######## Nao existe plano de rollback. Arquivo $rollback_file nao encontrado!"
		return
	}	
	createFoldersStructure("script");
	copyFilesToFolders("script"); 

	Set-Location $dir_root
	$sql_file="chamador-$DefinitionName-$BuildNumber.sql"

	Write-Output " " | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET DEFINE OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET ECHO ON;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET SERVEROUTPUT ON" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "@@chamador-status-$DefinitionName-$BuildNumber.sql" | Out-File -Encoding UTF8 -Append $sql_file	

	Get-Content $temp_db_files | ForEach-Object {
		$_ = $_.replace("\","/") 
		Write-Output "@@script/$_" | Out-File -Encoding UTF8 -Append $sql_file
	}
	
	Write-Output "@@chamador-status-$DefinitionName-$BuildNumber.sql" | Out-File -Encoding UTF8 -Append $sql_file	
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "/" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "QUIT" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "######## $sql_file criado com sucesso!"
}


#Gera o arquivo chamador-status
function createStatusCheck() {

	$sql_file="chamador-status-$DefinitionName-$BuildNumber.sql"
	
	Write-Output " " | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET SQLBLANKLINES ON;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET ECHO ON;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET SERVEROUTPUT ON;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "EXEC sys.UTL_RECOMP.recomp_parallel(4,'TRON2000');" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "EXEC sys.UTL_RECOMP.recomp_parallel(4,'SSR');" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "EXEC sys.UTL_RECOMP.recomp_parallel(4,'REPPARCADM');" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "EXEC sys.UTL_RECOMP.recomp_parallel(4,'TRP_XX_DL');" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "set pages 600 lines 300" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "col OWNER format a15" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "col DATA_ATUAL format a22" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "col OBJECT_NAME format a33" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SELECT to_char(SYSDATE, 'DD/MM/YYYY HH:MM:SS') AS DATA_ATUAL, count(object_name) AS OBJETOS_INVALIDOS, OWNER, OBJECT_NAME, OBJECT_TYPE FROM ALL_OBJECTS, GLOBAL_NAME, SYS.DUAL WHERE status = 'INVALID' AND owner in ('TRON2000','SSR','REPPARCADM','TRP_XX_DL') AND object_type not in ('JAVA CLASS') GROUP BY OWNER,OBJECT_NAME,OBJECT_TYPE order by OWNER,OBJECT_TYPE,OBJECT_NAME;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "SPOOL 'temp-invalid-objects.txt'" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SELECT count(object_name) AS OBJETOS_INVALIDOS FROM SYS.USER_OBJECTS WHERE status='INVALID' AND object_type not in ('JAVA CLASS');" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "col NAME format a33" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "col TEXT format a150" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "col TYPE format a16" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "select NAME,TYPE,SEQUENCE,LINE,TEXT from user_errors order by NAME,TYPE,LINE;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SPOOL off;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	##Write-Output "QUIT" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "######## $sql_file criado com sucesso!"
}


#Gera os arquivos gera-backup e chamador-backup
function createBackupPackageAndCaller() {

	createFoldersStructure("backup");
	copyFilesToFolders("backup"); 

	### Criando o arquivo gera-backup
	Set-Location $dir_root
	$sql_file="chamador-backup-$DefinitionName-$BuildNumber.sql"
	
	Write-Output " " | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET SERVEROUTPUT ON;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET PAGESIZE 0" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET LONG 1000000000" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET LONGCHUNKSIZE 1000000000" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET LINESIZE 32767" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET TRIMSPOOL ON" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET FEEDBACK OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET HEADING OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET ECHO OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET TIMING OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET VERIFY OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET DEFINE OFF" | Out-File -Encoding UTF8 -Append $sql_file
    Write-Output "begin
   dbms_metadata.set_transform_param (dbms_metadata.session_transform, 'SQLTERMINATOR', true);
   dbms_metadata.set_transform_param (dbms_metadata.session_transform, 'PRETTY', true);
end;
/" | Out-File -Encoding UTF8 -Append $sql_file

	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file




	Get-Content $temp_db_files | ForEach-Object {

		$file_name = getFileName($_);
		$_ = $_.replace("\","/") 
		
		Write-Output "SPOOL 'backup/$_'" | Out-File -Encoding UTF8 -Append $sql_file		
       Write-Output "SELECT DBMS_METADATA.GET_DDL(REPLACE(a.OBJECT_TYPE,CHR(32),'_'),a.OBJECT_NAME,a.OWNER) as script FROM dba_objects a WHERE OBJECT_NAME=replace(upper('$file_name'),'TRON2000_','') and  OWNER = 'TRON2000' ORDER BY a.OBJECT_TYPE , a.OBJECT_NAME ,a.OWNER;" | Out-File -Encoding UTF8 -Append $sql_file		
       Write-Output "SPOOL OFF;" | Out-File -Encoding UTF8 -Append $sql_file
		Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
		Write-Output "######## Script SQL (para backup) $_ criado com sucesso"
	}	
	
	Write-Output "QUIT" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "######## $sql_file criado com sucesso!"

	### Criando o arquivo chamador-backup
	Set-Location $dir_root
	$sql_file2="gera-backup-$DefinitionName-$BuildNumber.sql"

	Write-Output " " | Out-File -Encoding UTF8 -Append $sql_file2
	Write-Output "SET DEFINE OFF" | Out-File -Encoding UTF8 -Append $sql_file2
	Write-Output "SET ECHO ON;" | Out-File -Encoding UTF8 -Append $sql_file2
	Write-Output "SET SERVEROUTPUT ON" | Out-File -Encoding UTF8 -Append $sql_file2
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file2		

	Get-Content $temp_db_files | ForEach-Object {
		$_ = $_.replace("\","/") 
		Write-Output "@@backup/$_" | Out-File -Encoding UTF8 -Append $sql_file2
	}
	
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file2
	Write-Output "/" | Out-File -Encoding UTF8 -Append $sql_file2
	Write-Output "QUIT" | Out-File -Encoding UTF8 -Append $sql_file2
	
	Write-Output "######## $sql_file2 criado com sucesso!"
}


#Gera o arquivo chamador-rollback
function createRollbackCaller() {

	$error = validateFiles($rollback_file)
	if ($error -eq 1){
		Write-Output "######## Nao existe plano de rollback. Arquivo $rollback_file nao encontrado!"
		return
	}

	createFoldersStructure("rollback");
	copyFilesToFolders("rollback");	

	Set-Location $dir_root
	$sql_file="chamador-rollback-$DefinitionName-$BuildNumber.sql"
	Write-Output "######## Existe um plano de rollback. Criando script de rollback"

	Write-Output " " | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET DEFINE OFF" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET ECHO ON;" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "SET SERVEROUTPUT ON" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "@@chamador-status-$DefinitionName-$BuildNumber.sql" | Out-File -Encoding UTF8 -Append $sql_file	

	Get-Content $temp_rollback_file | ForEach-Object {
		$_ = $_.replace("\","/") 
		Write-Output "@@rollback/$_" | Out-File -Encoding UTF8 -Append $sql_file
	}

	Write-Output "@@chamador-status-$DefinitionName-$BuildNumber.sql" | Out-File -Encoding UTF8 -Append $sql_file	
	Write-Output "" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "/" | Out-File -Encoding UTF8 -Append $sql_file
	Write-Output "QUIT" | Out-File -Encoding UTF8 -Append $sql_file
	
	Write-Output "######## $sql_file criado com sucesso!"
}
 
#Retornar o nome do arquivo
function getFileName([string]$full_path){

	$full_path = $full_path.replace("\","/")
	$full_path = $full_path.replace("TRON2000_","")
	$full_path = $full_path.replace(".SQL","")
	$full_path = $full_path.replace(".sql","")			
	
	#Existe subdiretorio
	if($full_path.indexOf("/") -ne $full_path.LastIndexOf("/")){
		$begin_file_name = $full_path.LastIndexOf("/")+1
	}else{
	#Nao existe subdiretorio
		$begin_file_name = $full_path.indexOf("/")+1
	}

	$str_size = $full_path.length	
	$file_name_size = $str_size - $begin_file_name
	return $full_path.Substring($begin_file_name, $file_name_size).ToUpper()
}

#Retornar o nome do diretorio
function getFolderName([string]$full_path){

	$full_path = $full_path.replace("\","/")
	$full_path = $full_path.replace("TRON2000_","")
	$full_path = $full_path.replace(".SQL","")
	$full_path = $full_path.replace(".sql","")			
	
	#Existe subdiretorio
	if($full_path.indexOf("/") -ne $full_path.LastIndexOf("/")){
		$begin_file_name = $full_path.LastIndexOf("/")+1
	}else{
	#Nao existe subdiretorio
		$begin_file_name = $full_path.indexOf("/")+1
	}

	return $full_path.Substring(0, $begin_file_name).ToUpper()
}

createScriptCaller
createStatusCheck
createBackupPackageAndCaller
createRollbackCaller

Write-Output "################ Build $BuildNumber finalizado com sucesso #########################"
Write-Output "######################## Fim do Build $BuildNumber #################################"
