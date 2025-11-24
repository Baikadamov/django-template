from django.core.exceptions import ValidationError

class FileSizeValidator:
    def __init__(self, max_size_mb=5):
        self.max_size_mb = max_size_mb
        self.max_size_bytes = max_size_mb * 1024 * 1024
    
    def __call__(self, file):
        if file.size > self.max_size_bytes:
            raise ValidationError(
                f'Размер файла {file.size / (1024 * 1024):.2f} МБ превышает '
                f'максимально допустимый {self.max_size_mb} МБ',
                code='file_too_large'
            )
    
    def deconstruct(self):
        """
        Этот метод нужен Django для сериализации валидатора в миграциях.
        """
        return (
            f"{self.__module__}.{self.__class__.__name__}",  # путь к классу
            [],                                              # позиционные аргументы
            {"max_size_mb": self.max_size_mb},               # именованные аргументы
        )