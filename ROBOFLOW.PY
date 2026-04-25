

from roboflow import Roboflow
rf = Roboflow(api_key="7Zd1JparbF8KuAKRhBn8")
project = rf.workspace("namans-workspace-mznto").project("Banana Ripening Process")
dataset = project.version(1).download("multiclass")