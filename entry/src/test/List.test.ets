import localUnitTest from './LocalUnit.test';
import reminderModelTest from './ReminderModel.test';

export default function testsuite() {
  localUnitTest();
  reminderModelTest();
}
