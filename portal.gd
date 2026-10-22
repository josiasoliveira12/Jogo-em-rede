extends Area2D

func _on_body_entered(body: Node2D) -> void:
    var cena_principal := get_tree().current_scene
    if cena_principal != null and cena_principal.has_method("_on_portal_body_entered"):
        cena_principal._on_portal_body_entered(body)
