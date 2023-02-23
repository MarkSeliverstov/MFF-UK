<?php

class Model_Articles extends Model
{
	public function get_article_list($id = null)
	{
        $query = $query = 'SELECT * FROM `cms` ORDER BY id DESC;';
        $this->myDB->run_one_query($query);
        return $this->myDB->result;
	}

    public function get_article($id){
        $query = "SELECT * FROM `cms` WHERE id=${id};";
        $this->myDB->run_one_query($query);
        return $this->myDB->result;
    }

    public function save_edited_article($id, $content, $name){
        $query = "UPDATE `cms` SET `content`='$content' WHERE id=$id;";
        $this->myDB->run_one_query($query);
        $query = "UPDATE `cms` SET `title`='$name' WHERE id=$id;";
        $this->myDB->run_one_query($query);
    }

    public function create_article($title){
        $query = "SELECT MAX(id) FROM `cms`;";
        $this->myDB->run_one_query($query);

        $id = $this->myDB->result[0]["MAX(id)"] + 1;

        $query = "INSERT INTO `cms`(`id`, `title`, `content`, `like`, `dislike`) VALUES (${id},'${title}','', 0, 0);";
        echo $query;
        $this->myDB->run_one_query($query);
        return $id;
    }

    public function delete_article($id){
        $query = "DELETE FROM `cms` WHERE id=$id;";
        $this->myDB->run_one_query($query);
        if (empty($this->myDB->err)){
            echo json_encode(array('delete' => 'success'));
        }
        else{
            echo json_encode(array('delete' => 'dailed'));
        }
    }
}
