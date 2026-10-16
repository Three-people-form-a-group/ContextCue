import localUnitTest from './LocalUnit.test';
import reminderModelTest from './ReminderModel.test';
import reminderRepositoryTest from './ReminderRepository.test';
import reminderTriggerPortTest from './ReminderTriggerPort.test';

export default function testsuite() {
  localUnitTest();
  reminderModelTest();
  reminderRepositoryTest();
  reminderTriggerPortTest();
}
